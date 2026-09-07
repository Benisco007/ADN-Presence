import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, Supabase;

import '../models/presence_model.dart';
import '../models/user_model.dart';
import 'email_service.dart';

// Syncfusion XlsIO — insertion d'images dans XLSX
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

/// Résultat d'une génération de rapport.
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
    required this.excelPath,
    required this.pdfPath,
  });
}

class ExportService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const List<String> _nomsJours = [
    'Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim',
  ];

  // ─────────────────────────────────────────────
  // Helpers de date
  // ─────────────────────────────────────────────

  DateTime _debutSemaine([DateTime? reference]) {
    final DateTime now = reference ?? DateTime.now();
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  /// Numéro de semaine ISO 8601.
  int _numeroSemaine(DateTime date) {
    // Jeudi de la semaine courante (ISO : la semaine contenant le premier jeudi)
    final DateTime jeudi = date.add(Duration(days: 4 - date.weekday));
    final DateTime premierJanvier = DateTime(jeudi.year, 1, 1);
    return ((jeudi.difference(premierJanvier).inDays) / 7).floor() + 1;
  }

  String _nomFichierBase(DateTime debutSemaine) {
    final int semaine = _numeroSemaine(debutSemaine);
    final int annee = debutSemaine.year;
    return 'rapport_presence_Semaine_${semaine}_$annee';
  }

  // ─────────────────────────────────────────────
  // Récupération des données Firestore
  // ─────────────────────────────────────────────

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

  /// Récupère les noms de parcs depuis Firestore.
  /// En cas d'erreur de permission, retourne une map vide (les IDs seront affichés).
  Future<Map<String, String>> _nomsDesParcs() async {
    try {
      final snapshot = await _firestore.collection('parcs').get();
      return {
        for (final doc in snapshot.docs)
          doc.id: (doc.data()['nom'] as String?) ?? 'Parc sans nom',
      };
    } catch (_) {
      // PERMISSION_DENIED ou erreur réseau — on continue sans noms de parcs
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

  // ─────────────────────────────────────────────
  // Téléchargement d'images (signatures / logo)
  // ─────────────────────────────────────────────

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

  // ─────────────────────────────────────────────
  // MÉTHODE PRINCIPALE
  // ─────────────────────────────────────────────

  /// Génère le rapport Excel + PDF de la semaine et les pousse sur Supabase/Firestore.
  /// [reference] : si null, utilise la semaine courante.
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

    // ── Données ──
    final Map<String, UserModel> employes = await _tousLesEmployes();
    final Map<String, String> nomsParcs = await _nomsDesParcs();
    final List<PresenceModel> presences =
        await _presencesDeLaSemaine(debut, fin);

    // Index userId → {clé date → PresenceModel}
    final Map<String, Map<String, PresenceModel>> index = {};
    for (final p in presences) {
      final String cle =
          '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}-${p.date.day.toString().padLeft(2, '0')}';
      index.putIfAbsent(p.userId, () => {})[cle] = p;
    }

    final List<UserModel> listeEmployes = employes.values.toList()
      ..sort((a, b) => a.nom.compareTo(b.nom));

    // ── Pré-téléchargement des signatures ──
    final Map<String, Uint8List> signatures = {};
    for (final emp in listeEmployes) {
      if (emp.signatureUrl != null && emp.signatureUrl!.isNotEmpty) {
        final bytes = await _telechargerImage(emp.signatureUrl!);
        if (bytes != null) signatures[emp.id] = bytes;
      }
    }

    // ── Logo ──
    final Uint8List? logoBytes = await _logoBytes();

    // ── Noms de fichiers ──
    final String baseId = _nomFichierBase(debut);
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String excelNom = '${baseId}_$ts.xlsx';
    final String pdfNom = '${baseId}_$ts.pdf';

    // ── Génération Excel ──
    final String excelPath = await _construireExcel(
      nomFichier: excelNom,
      debut: debut,
      jours: jours,
      listeEmployes: listeEmployes,
      nomsParcs: nomsParcs,
      index: index,
      signatures: signatures,
      periode: periode,
    );

    // ── Génération PDF ──
    final String pdfPath = await _construirePdf(
      nomFichier: pdfNom,
      debut: debut,
      jours: jours,
      listeEmployes: listeEmployes,
      nomsParcs: nomsParcs,
      index: index,
      signatures: signatures,
      logoBytes: logoBytes,
      periode: periode,
    );

    // ── Upload Supabase ──
    final storage = Supabase.instance.client.storage.from('reports');

    await storage.upload(
      excelNom,
      File(excelPath),
      fileOptions: const FileOptions(
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        upsert: true,
      ),
    );
    await storage.upload(
      pdfNom,
      File(pdfPath),
      fileOptions: const FileOptions(
        contentType: 'application/pdf',
        upsert: true,
      ),
    );

    final String excelUrl = storage.getPublicUrl(excelNom);
    final String pdfUrl = storage.getPublicUrl(pdfNom);

    // ── Firestore ──
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
      excelPath: excelPath,
      pdfPath: pdfPath,
    );
  }

  // ─────────────────────────────────────────────
  // Génération Excel (Syncfusion XlsIO)
  // ─────────────────────────────────────────────

  Future<String> _construireExcel({
    required String nomFichier,
    required DateTime debut,
    required List<DateTime> jours,
    required List<UserModel> listeEmployes,
    required Map<String, String> nomsParcs,
    required Map<String, Map<String, PresenceModel>> index,
    required Map<String, Uint8List> signatures,
    required String periode,
  }) async {
    final xlsio.Workbook workbook = xlsio.Workbook();

    // ═══════════════════════════════════════
    // FEUILLE 1 — "Presences semaine"
    // ═══════════════════════════════════════
    final xlsio.Worksheet feuille1 = workbook.worksheets[0];
    feuille1.name = 'Presences semaine';

    // Couleurs
    const String bleuFonce = '#1558B0';
    const String bleuClair = '#1A73E8';

    // ── Titre ──
    final xlsio.Range titreCell = feuille1.getRangeByIndex(1, 1, 1, 12);
    titreCell.merge();
    titreCell.text =
        'Feuille de présence - Semaine ${_numeroSemaine(debut)} ($periode)';
    titreCell.cellStyle.bold = true;
    titreCell.cellStyle.backColor = bleuClair;
    titreCell.cellStyle.fontColor = '#FFFFFF';
    titreCell.cellStyle.fontSize = 12;
    titreCell.rowHeight = 22;

    // ── En-têtes ligne 2 ──
    final List<String> entetes = [
      'Prénom & Nom',
      'Poste',
      'Email',
      'Contact',
      'Nom du Parc',
    ];
    for (int c = 0; c < entetes.length; c++) {
      final xlsio.Range cell = feuille1.getRangeByIndex(2, c + 1);
      cell.text = entetes[c];
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = bleuFonce;
      cell.cellStyle.fontColor = '#FFFFFF';
    }
    // Colonnes jours
    for (int j = 0; j < jours.length; j++) {
      final DateTime jour = jours[j];
      final String label =
          '${_nomsJours[jour.weekday - 1]} ${jour.day.toString().padLeft(2, '0')}/'
          '${jour.month.toString().padLeft(2, '0')}';
      final xlsio.Range cell = feuille1.getRangeByIndex(2, 6 + j);
      cell.text = label;
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = bleuFonce;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
    }

    // ── Données employés ──
    final DateTime aujourd = DateTime.now();
    for (int e = 0; e < listeEmployes.length; e++) {
      final UserModel emp = listeEmployes[e];
      final int row = 3 + e;
      final String bgLigne = (e % 2 == 0) ? '#FFFFFF' : '#F0F4FF';

      void ecrit(int col, String texte, {String? bg, String? fg, bool center = false}) {
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
          texte = 'Présent $h\n(auto)';
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

    // ── Largeurs colonnes ──
    feuille1.setColumnWidthInPixels(1, 160);
    feuille1.setColumnWidthInPixels(2, 110);
    feuille1.setColumnWidthInPixels(3, 180);
    feuille1.setColumnWidthInPixels(4, 110);
    feuille1.setColumnWidthInPixels(5, 130);
    for (int j = 0; j < 7; j++) {
      feuille1.setColumnWidthInPixels(6 + j, 100);
    }

    // ═══════════════════════════════════════
    // FEUILLE 2 — "ADN Présence"
    // ═══════════════════════════════════════
    final xlsio.Worksheet feuille2 = workbook.worksheets.addWithName('ADN Présence');

    // En-têtes
    final List<String> entetes2 = [
      'Prénom & Nom',
      'Poste',
      'Email',
      'Contact',
      'Nom du Parc',
      'Signature',
    ];
    for (int c = 0; c < entetes2.length; c++) {
      final xlsio.Range cell = feuille2.getRangeByIndex(1, c + 1);
      cell.text = entetes2[c];
      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = bleuFonce;
      cell.cellStyle.fontColor = '#FFFFFF';
    }

    // Données + images de signature
    const double hauteurLigneSignature = 60; // points
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

      // Hauteur de ligne pour accueillir l'image
      feuille2.getRangeByIndex(row, 1).rowHeight = hauteurLigneSignature;

      final Uint8List? sigBytes = signatures[emp.id];
      if (sigBytes != null) {
        // Insertion de l'image dans la cellule de la colonne Signature (col 6)
        try {
          final xlsio.Picture picture = feuille2.pictures.addStream(
            row, // ligne (1-indexed)
            6,   // colonne (1-indexed)
            sigBytes,
          );
          picture.height = (hauteurLigneSignature * 1.33).round();
          picture.width = 120;
          // Pas de texte fallback — l'image est présente
        } catch (e) {
          // Format non supporté — afficher un message neutre (pas de lien)
          feuille2.getRangeByIndex(row, 6).text = 'Image non supportée';
          feuille2.getRangeByIndex(row, 6).cellStyle.fontColor = '#999999';
        }
      } else {
        feuille2.getRangeByIndex(row, 6).text = 'Aucune signature';
        feuille2.getRangeByIndex(row, 6).cellStyle.fontColor = '#AAAAAA';
      }
    }

    // Largeurs colonnes feuille 2
    feuille2.setColumnWidthInPixels(1, 160);
    feuille2.setColumnWidthInPixels(2, 110);
    feuille2.setColumnWidthInPixels(3, 180);
    feuille2.setColumnWidthInPixels(4, 110);
    feuille2.setColumnWidthInPixels(5, 130);
    feuille2.setColumnWidthInPixels(6, 150);

    // ── Sauvegarde ──
    final List<int> bytes = workbook.saveAsStream();
    workbook.dispose();

    final Directory tempDir = await getTemporaryDirectory();
    final String path = '${tempDir.path}/$nomFichier';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  // ─────────────────────────────────────────────
  // Génération PDF
  // ─────────────────────────────────────────────

  Future<String> _construirePdf({
    required String nomFichier,
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

    // Logo PDF
    pw.ImageProvider? logoPdf;
    if (logoBytes != null) {
      logoPdf = pw.MemoryImage(logoBytes);
    }

    // Thème couleurs PDF
    const PdfColor bleuPrimaire = PdfColor.fromInt(0xFF1A73E8);
    const PdfColor bleuFonce = PdfColor.fromInt(0xFF1558B0);
    const PdfColor grisClaire = PdfColor.fromInt(0xFFF5F7FA);
    const PdfColor vertPresent = PdfColor.fromInt(0xFF1B5E20);
    const PdfColor rougeAbsent = PdfColor.fromInt(0xFFC62828);
    const PdfColor orangeManuel = PdfColor.fromInt(0xFFE65100);

    final DateTime aujourd = DateTime.now();

    // ── Helper cellule tableau ──
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
        // ── En-tête de page ──
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
                  pw.Text('ADN Présence',
                      style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: bleuPrimaire)),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'RAPPORT DE PRÉSENCE - Semaine ${_numeroSemaine(debut)}',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text('Période : $periode',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                        'Généré le ${aujourd.day}/${aujourd.month}/${aujourd.year}',
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
        // ── Pied de page ──
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('ADN Présence - Rapport confidentiel',
                style:
                    pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
            pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
                style:
                    pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
          ],
        ),
        build: (context) => [
          // ── Section 1 : tableau des présences ──
          pw.Text(
            'Tableau des présences hebdomadaires',
            style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: bleuFonce),
          ),
          pw.SizedBox(height: 6),
          // ── Tableau présences (portrait par employé, sans colonne Type) ──
          pw.Table(
            columnWidths: {
              0: const pw.FlexColumnWidth(2.0),  // Nom
              1: const pw.FlexColumnWidth(1.3),  // Poste
              2: const pw.FlexColumnWidth(1.8),  // Email
              3: const pw.FlexColumnWidth(1.2),  // Contact
              4: const pw.FlexColumnWidth(1.4),  // Parc
              5: const pw.FlexColumnWidth(1.0),  // Lun
              6: const pw.FlexColumnWidth(1.0),  // Mar
              7: const pw.FlexColumnWidth(1.0),  // Mer
              8: const pw.FlexColumnWidth(1.0),  // Jeu
              9: const pw.FlexColumnWidth(1.0),  // Ven
              10: const pw.FlexColumnWidth(1.0), // Sam
              11: const pw.FlexColumnWidth(1.0), // Dim
              12: const pw.FlexColumnWidth(1.8), // Signature
            },
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: [
              // En-tête
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: bleuFonce),
                children: [
                  cellule('Prénom & Nom', gras: true, couleurTexte: PdfColors.white),
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
              // Données — une ligne par employé avec signature image
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
                    // Colonne Signature — image réelle (remplace la colonne Type)
                    pw.Container(
                      height: 50,
                      padding: const pw.EdgeInsets.all(0),
                      color: bgLigne,
                      child: sigBytes != null
                          ? pw.Image(
                              pw.MemoryImage(sigBytes),
                              fit: pw.BoxFit.contain,
                            )
                          : pw.Center(
                              child: pw.Text(
                                'Aucune',
                                style: pw.TextStyle(
                                    fontSize: 6,
                                    color: PdfColors.grey400,
                                    fontStyle: pw.FontStyle.italic),
                              ),
                            ),
                    ),
                  ],
                );
              }),
            ],
          ),

          // (La section signatures est maintenant intégrée directement dans le tableau ci-dessus)
        ],
      ),
    );

    final Directory tempDir = await getTemporaryDirectory();
    final String path = '${tempDir.path}/$nomFichier';
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  // ─────────────────────────────────────────────
  // Envoi mail hebdomadaire (conservé, inchangé)
  // ─────────────────────────────────────────────

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
    } catch (e) {
      return false;
    }
  }
}