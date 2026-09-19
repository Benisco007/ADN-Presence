// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, Supabase;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../models/presence_model.dart';
import '../models/user_model.dart';
import 'email_service.dart';

/// Résultat d'une génération de rapport (version web).
class RapportResult {
  final String rapportId;
  final String excelUrl;
  final String pdfUrl;
  final String excelPath;
  final String pdfPath;

  const RapportResult({
    required this.rapportId,
    required this.excelUrl,
    required this.pdfUrl,
    this.excelPath = '',
    this.pdfPath = '',
  });
}

/// Version Web de ExportService.
/// Génère Excel + PDF en mémoire et les uploade sur Supabase via uploadBinary.
class ExportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List<String> _nomsJours = [
    'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim',
  ];

  DateTime _debutSemaine([DateTime? reference]) {
    final DateTime now = reference ?? DateTime.now();
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  int _numeroSemaine(DateTime date) {
    final DateTime jeudi = date.add(Duration(days: 4 - date.weekday));
    final DateTime premierJanvier = DateTime(jeudi.year, 1, 1);
    return ((jeudi.difference(premierJanvier).inDays) / 7).floor() + 1;
  }

  String _nomFichierBase(DateTime debutSemaine) {
    final int semaine = _numeroSemaine(debutSemaine);
    final int annee = debutSemaine.year;
    return 'rapport_presence_Semaine_${semaine}_$annee';
  }

  Future<Map<String, UserModel>> _tousLesEmployes() async {
    final QuerySnapshot snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employe')
        .get();
    final Map<String, UserModel> users = {};
    for (final doc in snapshot.docs) {
      users[doc.id] =
          UserModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    }
    return users;
  }

  Future<Map<String, String>> _nomsDesParcs() async {
    try {
      final snapshot = await _firestore.collection('parcs').get();
      return {
        for (final doc in snapshot.docs)
          doc.id: (doc.data()['nom'] as String?) ?? 'Parc sans nom',
      };
    } catch (_) {
      return {};
    }
  }

  Future<List<PresenceModel>> _presencesDeLaSemaine(
    DateTime debutSemaine,
    DateTime finSemaine,
  ) async {
    final QuerySnapshot snapshot =
        await _firestore.collection('presences').get();
    return snapshot.docs
        .map((doc) =>
            PresenceModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .where((p) =>
            (p.date.isAfter(debutSemaine) ||
                p.date.isAtSameMomentAs(debutSemaine)) &&
            p.date.isBefore(finSemaine))
        .toList();
  }

  Future<Uint8List?> _telechargerImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> _logoBytes() async {
    try {
      final data = await rootBundle.load('assets/images/logo.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<RapportResult> genererRapportSemaine({DateTime? reference}) async {
    final DateTime debut = _debutSemaine(reference);
    final List<DateTime> jours =
        List.generate(7, (i) => debut.add(Duration(days: i)));
    final DateTime fin = jours.last.add(const Duration(days: 1));
    final DateTime finAffichage = jours.last;

    final String periode =
        '${debut.day.toString().padLeft(2, '0')}/${debut.month.toString().padLeft(2, '0')}'
        ' au '
        '${finAffichage.day.toString().padLeft(2, '0')}/'
        '${finAffichage.month.toString().padLeft(2, '0')}/'
        '${finAffichage.year}';

    final Map<String, UserModel> employes = await _tousLesEmployes();
    final Map<String, String> nomsParcs = await _nomsDesParcs();
    final List<PresenceModel> presences =
        await _presencesDeLaSemaine(debut, fin);

    final Map<String, Map<String, PresenceModel>> index = {};
    for (final p in presences) {
      final String cle =
          '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}-${p.date.day.toString().padLeft(2, '0')}';
      index.putIfAbsent(p.userId, () => {})[cle] = p;
    }

    final List<UserModel> listeEmployes = employes.values.toList()
      ..sort((a, b) => a.nom.compareTo(b.nom));

    final Map<String, Uint8List> signatures = {};
    for (final emp in listeEmployes) {
      if (emp.signatureUrl != null && emp.signatureUrl!.isNotEmpty) {
        final bytes = await _telechargerImage(emp.signatureUrl!);
        if (bytes != null) signatures[emp.id] = bytes;
      }
    }

    final Uint8List? logoBytes = await _logoBytes();

    final String baseId = _nomFichierBase(debut);
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String excelNom = '${baseId}_$ts.xlsx';
    final String pdfNom = '${baseId}_$ts.pdf';

    final Uint8List excelBytes = await _construireExcelBytes(
      debut: debut,
      jours: jours,
      listeEmployes: listeEmployes,
      nomsParcs: nomsParcs,
      index: index,
      signatures: signatures,
      periode: periode,
    );

    final Uint8List pdfBytes = await _construirePdfBytes(
      debut: debut,
      jours: jours,
      listeEmployes: listeEmployes,
      nomsParcs: nomsParcs,
      index: index,
      signatures: signatures,
      logoBytes: logoBytes,
      periode: periode,
    );

    final storage = Supabase.instance.client.storage.from('reports');

    await storage.uploadBinary(
      excelNom,
      excelBytes,
      fileOptions: const FileOptions(
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        upsert: true,
      ),
    );
    await storage.uploadBinary(
      pdfNom,
      pdfBytes,
      fileOptions: const FileOptions(
        contentType: 'application/pdf',
        upsert: true,
      ),
    );

    final String excelUrl = storage.getPublicUrl(excelNom);
    final String pdfUrl = storage.getPublicUrl(pdfNom);

    final String? userId = FirebaseAuth.instance.currentUser?.uid;
    final String rapportId = baseId;

    await _firestore.collection('rapports').doc(rapportId).set({
      'rapportId': rapportId,
      'semaine': _numeroSemaine(debut),
      'annee': debut.year,
      'debut': Timestamp.fromDate(debut),
      'fin': Timestamp.fromDate(fin),
      'excelUrl': excelUrl,
      'pdfUrl': pdfUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': userId ?? '',
    }, SetOptions(merge: true));

    return RapportResult(
      rapportId: rapportId,
      excelUrl: excelUrl,
      pdfUrl: pdfUrl,
    );
  }

  Future<Uint8List> _construireExcelBytes({
    required DateTime debut,
    required List<DateTime> jours,
    required List<UserModel> listeEmployes,
    required Map<String, String> nomsParcs,
    required Map<String, Map<String, PresenceModel>> index,
    required Map<String, Uint8List> signatures,
    required String periode,
  }) async {
    final xlsio.Workbook workbook = xlsio.Workbook();

    const String bleuFonce = '#1558B0';
    const String bleuClair = '#1A73E8';

    final xlsio.Worksheet feuille1 = workbook.worksheets[0];
    feuille1.name = 'Presences semaine';

    final xlsio.Range titreCell = feuille1.getRangeByIndex(1, 1, 1, 12);
    titreCell.merge();
    titreCell.text =
        'Feuille de presence - Semaine ${_numeroSemaine(debut)} ($periode)';
    titreCell.cellStyle.bold = true;
    titreCell.cellStyle.backColor = bleuClair;
    titreCell.cellStyle.fontColor = '#FFFFFF';
    titreCell.cellStyle.fontSize = 12;
    titreCell.rowHeight = 22;

    final List<String> entetes = [
      'Prenom & Nom', 'Poste', 'Email', 'Contact', 'Nom du Parc',
    ];
    for (int c = 0; c < entetes.length; c++) {
      final xlsio.Range cell = feuille1.getRangeByIndex(2, c + 1);
      cell.text = entetes[c];
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = bleuFonce;
      cell.cellStyle.fontColor = '#FFFFFF';
    }
    for (int j = 0; j < jours.length; j++) {
      final DateTime jour = jours[j];
      final String label =
          '${_nomsJours[jour.weekday - 1]} ${jour.day.toString().padLeft(2, '0')}/${jour.month.toString().padLeft(2, '0')}';
      final xlsio.Range cell = feuille1.getRangeByIndex(2, 6 + j);
      cell.text = label;
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = bleuFonce;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
    }

    final DateTime aujourd = DateTime.now();
    for (int e = 0; e < listeEmployes.length; e++) {
      final UserModel emp = listeEmployes[e];
      final int row = 3 + e;
      final String bgLigne = (e % 2 == 0) ? '#FFFFFF' : '#F0F4FF';

      void ecrit(int col, String texte,
          {String? bg, String? fg, bool center = false}) {
        final xlsio.Range cell = feuille1.getRangeByIndex(row, col);
        cell.text = texte;
        cell.cellStyle.backColor = bg ?? bgLigne;
        if (fg != null) cell.cellStyle.fontColor = fg;
        if (center) cell.cellStyle.hAlign = xlsio.HAlignType.center;
      }

      ecrit(1, '${emp.prenom} ${emp.nom}');
      feuille1.getRangeByIndex(row, 1).cellStyle.bold = true;
      ecrit(2, emp.poste);
      ecrit(3, emp.email);
      ecrit(4, emp.contact ?? '');
      ecrit(5, nomsParcs[emp.parcId] ?? 'Sans parc');

      for (int j = 0; j < jours.length; j++) {
        final DateTime jour = jours[j];
        final String cle =
            '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';
        final PresenceModel? p = index[emp.id]?[cle];

        String texte;
        String bg;
        String fg;

        if (p == null) {
          final bool estFutur = jour.isAfter(aujourd);
          texte = estFutur ? '-' : 'Absent';
          bg = estFutur ? bgLigne : '#FDECEA';
          fg = estFutur ? '#AAAAAA' : '#C62828';
        } else if (p.type == 'automatique') {
          final String h =
              '${p.heureArrivee.hour}h${p.heureArrivee.minute.toString().padLeft(2, '0')}';
          texte = 'Present $h (auto)';
          bg = '#E6F4EA';
          fg = '#1B5E20';
        } else {
          final String h =
              '${p.heureArrivee.hour}h${p.heureArrivee.minute.toString().padLeft(2, '0')}';
          texte = 'Manuel $h';
          bg = '#FFF8E1';
          fg = '#E65100';
        }

        ecrit(6 + j, texte, bg: bg, fg: fg, center: true);
      }
    }

    feuille1.setColumnWidthInPixels(1, 160);
    feuille1.setColumnWidthInPixels(2, 110);
    feuille1.setColumnWidthInPixels(3, 180);
    feuille1.setColumnWidthInPixels(4, 110);
    feuille1.setColumnWidthInPixels(5, 130);
    for (int j = 0; j < 7; j++) {
      feuille1.setColumnWidthInPixels(6 + j, 100);
    }

    final xlsio.Worksheet feuille2 =
        workbook.worksheets.addWithName('ADN Presence');

    final List<String> entetes2 = [
      'Prenom & Nom', 'Poste', 'Email', 'Contact', 'Nom du Parc', 'Signature',
    ];
    for (int c = 0; c < entetes2.length; c++) {
      final xlsio.Range cell = feuille2.getRangeByIndex(1, c + 1);
      cell.text = entetes2[c];
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = bleuFonce;
      cell.cellStyle.fontColor = '#FFFFFF';
    }

    const double hauteurLigneSignature = 60;
    for (int e = 0; e < listeEmployes.length; e++) {
      final UserModel emp = listeEmployes[e];
      final int row = 2 + e;
      final String bgLigne = (e % 2 == 0) ? '#FFFFFF' : '#F0F4FF';

      void ecrit2(int col, String texte) {
        final xlsio.Range cell = feuille2.getRangeByIndex(row, col);
        cell.text = texte;
        cell.cellStyle.backColor = bgLigne;
      }

      ecrit2(1, '${emp.prenom} ${emp.nom}');
      feuille2.getRangeByIndex(row, 1).cellStyle.bold = true;
      ecrit2(2, emp.poste);
      ecrit2(3, emp.email);
      ecrit2(4, emp.contact ?? '');
      ecrit2(5, nomsParcs[emp.parcId] ?? 'Sans parc');
      feuille2.getRangeByIndex(row, 1).rowHeight = hauteurLigneSignature;

      final Uint8List? sigBytes = signatures[emp.id];
      if (sigBytes != null) {
        try {
          final xlsio.Picture picture =
              feuille2.pictures.addStream(row, 6, sigBytes);
          picture.height = (hauteurLigneSignature * 1.33).round();
          picture.width = 120;
        } catch (_) {
          feuille2.getRangeByIndex(row, 6).text = 'Image non supportee';
          feuille2.getRangeByIndex(row, 6).cellStyle.fontColor = '#999999';
        }
      } else {
        feuille2.getRangeByIndex(row, 6).text = 'Aucune signature';
        feuille2.getRangeByIndex(row, 6).cellStyle.fontColor = '#AAAAAA';
      }
    }

    feuille2.setColumnWidthInPixels(1, 160);
    feuille2.setColumnWidthInPixels(2, 110);
    feuille2.setColumnWidthInPixels(3, 180);
    feuille2.setColumnWidthInPixels(4, 110);
    feuille2.setColumnWidthInPixels(5, 130);
    feuille2.setColumnWidthInPixels(6, 150);

    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _construirePdfBytes({
    required DateTime debut,
    required List<DateTime> jours,
    required List<UserModel> listeEmployes,
    required Map<String, String> nomsParcs,
    required Map<String, Map<String, PresenceModel>> index,
    required Map<String, Uint8List> signatures,
    required Uint8List? logoBytes,
    required String periode,
  }) async {
    final pw.Document doc = pw.Document();

    pw.ImageProvider? logoPdf;
    if (logoBytes != null) {
      logoPdf = pw.MemoryImage(logoBytes);
    }

    const PdfColor bleuPrimaire = PdfColor.fromInt(0xFF1A73E8);
    const PdfColor bleuFonce = PdfColor.fromInt(0xFF1558B0);
    const PdfColor grisClaire = PdfColor.fromInt(0xFFF5F7FA);
    const PdfColor vertPresent = PdfColor.fromInt(0xFF1B5E20);
    const PdfColor rougeAbsent = PdfColor.fromInt(0xFFC62828);
    const PdfColor orangeManuel = PdfColor.fromInt(0xFFE65100);

    final DateTime aujourd = DateTime.now();

    pw.Widget cellule(
      String texte, {
      bool gras = false,
      PdfColor? bg,
      PdfColor couleurTexte = PdfColors.black,
      pw.Alignment align = pw.Alignment.centerLeft,
    }) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        color: bg,
        child: pw.Align(
          alignment: align,
          child: pw.Text(
            texte,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: couleurTexte,
            ),
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logoPdf != null)
                  pw.Image(logoPdf, width: 80, height: 40,
                      fit: pw.BoxFit.contain)
                else
                  pw.Text('ADN Presence',
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: bleuPrimaire)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'RAPPORT DE PRESENCE - Semaine ${_numeroSemaine(debut)}',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text('Periode : $periode',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                        'Genere le ${aujourd.day}/${aujourd.month}/${aujourd.year}',
                        style: pw.TextStyle(
                            fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Divider(color: bleuPrimaire, thickness: 1.5),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('ADN Presence - Rapport confidentiel',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
            pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          ],
        ),
        build: (context) => [
          pw.Text(
            'Tableau des presences hebdomadaires',
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: bleuFonce),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2.0),
              1: const pw.FlexColumnWidth(1.3),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.4),
              5: const pw.FlexColumnWidth(1.0),
              6: const pw.FlexColumnWidth(1.0),
              7: const pw.FlexColumnWidth(1.0),
              8: const pw.FlexColumnWidth(1.0),
              9: const pw.FlexColumnWidth(1.0),
              10: const pw.FlexColumnWidth(1.0),
              11: const pw.FlexColumnWidth(1.0),
              12: const pw.FlexColumnWidth(1.8),
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: bleuFonce),
                children: [
                  cellule('Prenom & Nom', gras: true, couleurTexte: PdfColors.white),
                  cellule('Poste', gras: true, couleurTexte: PdfColors.white),
                  cellule('Email', gras: true, couleurTexte: PdfColors.white),
                  cellule('Contact', gras: true, couleurTexte: PdfColors.white),
                  cellule('Parc', gras: true, couleurTexte: PdfColors.white),
                  ...jours.map((j) => cellule(
                        '${_nomsJours[j.weekday - 1]}\n${j.day.toString().padLeft(2, '0')}/${j.month.toString().padLeft(2, '0')}',
                        gras: true,
                        couleurTexte: PdfColors.white,
                        align: pw.Alignment.center,
                      )),
                  cellule('Signature', gras: true, couleurTexte: PdfColors.white,
                      align: pw.Alignment.center),
                ],
              ),
              ...listeEmployes.asMap().entries.map((entry) {
                final int e = entry.key;
                final UserModel emp = entry.value;
                final PdfColor bgLigne =
                    (e % 2 == 0) ? PdfColors.white : grisClaire;
                final Uint8List? sigBytes = signatures[emp.id];

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: bgLigne),
                  children: [
                    cellule('${emp.prenom} ${emp.nom}', gras: true),
                    cellule(emp.poste),
                    cellule(emp.email),
                    cellule(emp.contact ?? ''),
                    cellule(nomsParcs[emp.parcId] ?? emp.parcId ?? 'Sans parc'),
                    ...jours.map((jour) {
                      final String cle =
                          '${jour.year}-${jour.month.toString().padLeft(2, '0')}-${jour.day.toString().padLeft(2, '0')}';
                      final PresenceModel? p = index[emp.id]?[cle];

                      String texte;
                      PdfColor? bg;
                      PdfColor fg;

                      if (p == null) {
                        final bool futur = jour.isAfter(aujourd);
                        texte = futur ? '-' : 'Absent';
                        bg = futur ? null : const PdfColor.fromInt(0xFFFDECEA);
                        fg = futur ? PdfColors.grey400 : rougeAbsent;
                      } else if (p.type == 'automatique') {
                        final String h =
                            '${p.heureArrivee.hour}h${p.heureArrivee.minute.toString().padLeft(2, '0')}';
                        texte = h;
                        bg = const PdfColor.fromInt(0xFFE6F4EA);
                        fg = vertPresent;
                      } else {
                        final String h =
                            '${p.heureArrivee.hour}h${p.heureArrivee.minute.toString().padLeft(2, '0')}';
                        texte = h;
                        bg = const PdfColor.fromInt(0xFFFFF8E1);
                        fg = orangeManuel;
                      }

                      return cellule(texte,
                          bg: bg,
                          couleurTexte: fg,
                          align: pw.Alignment.center);
                    }),
                    pw.Container(
                      height: 50,
                      color: bgLigne,
                      child: sigBytes != null
                          ? pw.Image(pw.MemoryImage(sigBytes),
                              fit: pw.BoxFit.contain)
                          : pw.Center(
                              child: pw.Text('Aucune',
                                  style: pw.TextStyle(
                                      fontSize: 6,
                                      color: PdfColors.grey400,
                                      fontStyle: pw.FontStyle.italic)),
                            ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );

    return await doc.save();
  }

  Future<bool> envoyerMailHebdomadaire() async {
    try {
      final DateTime debutSemaine = _debutSemaine();
      final DateTime finSemaine = debutSemaine.add(const Duration(days: 7));
      final DateTime maintenant = DateTime.now();

      final List<PresenceModel> presences =
          await _presencesDeLaSemaine(debutSemaine, finSemaine);
      final Map<String, UserModel> employes = await _tousLesEmployes();

      final DateTime finAffichage = debutSemaine.add(const Duration(days: 6));
      final String semaine =
          'S${_numeroSemaine(maintenant)} ${maintenant.year}';
      final String periode =
          '${debutSemaine.day}/${debutSemaine.month} au '
          '${finAffichage.day}/${finAffichage.month}/${finAffichage.year}';

      final Set<String> userIdsPresents =
          presences.map((p) => p.userId).toSet();
      final int nombrePresents =
          presences.where((p) => p.type == 'automatique').length;
      final int nombreManuels =
          presences.where((p) => p.type == 'manuel').length;
      int nombreAbsents = (employes.length * 5) - userIdsPresents.length;
      if (nombreAbsents < 0) nombreAbsents = 0;

      return await EmailService.envoyerRapportHebdomadaire(
        semaine: semaine,
        periode: periode,
        nombrePresents: nombrePresents,
        nombreManuels: nombreManuels,
        nombreAbsents: nombreAbsents,
      );
    } catch (_) {
      return false;
    }
  }
}
