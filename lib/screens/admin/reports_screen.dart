import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/export_service.dart' if (dart.library.html) '../../services/export_service_web.dart';
import '../../services/file_helper.dart' if (dart.library.html) '../../services/file_helper_web.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _isGenerating = false;
  bool _isSendingEmail = false;

  // ── Génération du rapport de la semaine courante ──
  Future<void> _generateReport() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '⏳ Génération en cours… La création des fichiers Excel et PDF peut prendre quelques instants. Veuillez garder la fenêtre ouverte.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          duration: Duration(minutes: 3),
          backgroundColor: Color(0xFF1A73E8),
        ),
      );
    }

    try {
      await ExportService().genererRapportSemaine();
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rapport généré avec succès ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Génération impossible : $error'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ── Envoi du résumé statistique par mail via EmailJS ──
  Future<void> _envoyerMail() async {
    if (_isSendingEmail) return;
    setState(() => _isSendingEmail = true);
    try {
      final succes = await ExportService().envoyerMailHebdomadaire();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(succes
                ? '📧 Résumé hebdomadaire envoyé par mail ✓'
                : 'Échec de l\'envoi mail. Vérifiez votre connexion.'),
            backgroundColor: succes ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingEmail = false);
    }
  }

  // ── Téléchargement vers le dossier Downloads ──
  Future<String?> _telecharger(String url, String nomFichier) async {
    if (kIsWeb) {
      final downloadUrl = Uri.parse(url).replace(queryParameters: {
        ...Uri.parse(url).queryParameters,
        'download': nomFichier,
      });
      await launchUrl(downloadUrl, mode: LaunchMode.externalApplication);
      return null;
    }
    // Sur Android >= 10 (SDK 29+), on n'a plus besoin de WRITE_EXTERNAL_STORAGE
    // pour écrire dans /storage/emulated/0/Download.
    // Sur Android <= 9, on demande la permission.
    if (!kIsWeb) {
      await FileHelper.requestStoragePermissionIfNeeded();
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Téléchargement refusé (${response.statusCode})');
    }

    // Dossier Downloads accessible à l'utilisateur
    final String dirPath = await FileHelper.getDownloadsDirectory();

    // On ajoute un timestamp au nom du fichier pour éviter les conflits d'écrasement (Permission denied)
    final String extension = nomFichier.contains('.') ? nomFichier.split('.').last : '';
    final String nomSansExt = nomFichier.contains('.') ? nomFichier.substring(0, nomFichier.lastIndexOf('.')) : nomFichier;
    final String nomUnique = '${nomSansExt}_${DateTime.now().millisecondsSinceEpoch}.$extension';

    final String chemin = '$dirPath/$nomUnique';
    await FileHelper.saveFileBytes(chemin, response.bodyBytes);
    return chemin;
  }

  // ── Ouvrir un fichier local ──
  Future<void> _ouvrirFichier(String chemin) async {
    try {
      await FileHelper.openFile(chemin);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  // ── Partage des deux fichiers ──
  Future<void> _partagerDeuxFichiers(
    String excelUrl,
    String pdfUrl,
    Map<String, dynamic> data,
  ) async {
    try {
      if (kIsWeb) {
        await _voirDansNavigateur(excelUrl);
        await _voirDansNavigateur(pdfUrl);
        return;
      }
      final String tempDirPath = await FileHelper.getTemporaryDirPath();
      final String semStr =
          'S${data['semaine']}_${data['annee']}';

      // Noms propres pour le partage
      final String excelNom =
          'rapport_presence_Semaine_${data['semaine']}_${data['annee']}.xlsx';
      final String pdfNom =
          'rapport_presence_Semaine_${data['semaine']}_${data['annee']}.pdf';

      // Téléchargement en parallèle dans le dossier temp pour Share
      final results = await Future.wait([
        http.get(Uri.parse(excelUrl)),
        http.get(Uri.parse(pdfUrl)),
      ]);

      final String excelPath = '$tempDirPath/$excelNom';
      final String pdfPath = '$tempDirPath/$pdfNom';

      await FileHelper.saveFileBytes(excelPath, results[0].bodyBytes);
      await FileHelper.saveFileBytes(pdfPath, results[1].bodyBytes);

      await Share.shareXFiles(
        [XFile(excelPath), XFile(pdfPath)],
        subject: 'Rapport de présence — $semStr',
        text: 'Veuillez trouver ci-joint le rapport de présence de la semaine $semStr.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Partage impossible : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Contournement du cache HTTP / CDN Supabase ──
  String _freshUrl(String url) {
    final uri = Uri.parse(url);
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['t'] = DateTime.now().millisecondsSinceEpoch.toString();
    return uri.replace(queryParameters: queryParams).toString();
  }

  // ── Affichage dans le navigateur ──
  Future<void> _voirDansNavigateur(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Impossible d\'ouvrir $url');
    }
  }

  // ── Action sur un rapport (depuis popup) ──
  Future<void> _action(
    String type,
    Map<String, dynamic> data,
    String docId,
  ) async {
    final String? excelUrl = data['excelUrl'] as String?;
    final String? pdfUrl = data['pdfUrl'] as String?;
    final int semaine = (data['semaine'] as num?)?.toInt() ?? 0;
    final int annee = (data['annee'] as num?)?.toInt() ?? 0;
    final String excelNom =
        'rapport_presence_Semaine_${semaine}_$annee.xlsx';
    final String pdfNom =
        'rapport_presence_Semaine_${semaine}_$annee.pdf';

    try {
      switch (type) {
        case 'viewPdf':
          if (pdfUrl == null || pdfUrl.isEmpty) return;
          await _voirDansNavigateur(_freshUrl(pdfUrl));
          break;

        case 'downloadPdf':
          if (pdfUrl == null || pdfUrl.isEmpty) return;
          final chemin = await _telecharger(_freshUrl(pdfUrl), pdfNom);
          if (chemin != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('PDF sauvegardé : $chemin'),
                action: SnackBarAction(
                  label: 'Ouvrir',
                  onPressed: () => _ouvrirFichier(chemin),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          break;

        case 'viewExcel':
          if (excelUrl == null || excelUrl.isEmpty) return;
          await _voirDansNavigateur(_freshUrl(excelUrl));
          break;

        case 'downloadExcel':
          if (excelUrl == null || excelUrl.isEmpty) return;
          final chemin = await _telecharger(_freshUrl(excelUrl), excelNom);
          if (chemin != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Excel sauvegardé : $chemin'),
                action: SnackBarAction(
                  label: 'Ouvrir',
                  onPressed: () => _ouvrirFichier(chemin),
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
          break;

        case 'shareAll':
          if (excelUrl == null || pdfUrl == null) return;
          await _partagerDeuxFichiers(_freshUrl(excelUrl), _freshUrl(pdfUrl), data);
          break;

        case 'delete':
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Supprimer ce rapport ?'),
              content: Text('Voulez-vous supprimer le rapport Semaine $semaine — $annee ?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Supprimer'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await FirebaseFirestore.instance.collection('rapports').doc(docId).delete();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Rapport supprimé avec succès'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
          break;

        case 'rename':
          String currentName = data['nomPersonnalise'] as String? ?? '';
          final newName = await showDialog<String>(
            context: context,
            builder: (ctx) {
              final controller = TextEditingController(text: currentName);
              return AlertDialog(
                title: const Text('Renommer le rapport'),
                content: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Ex: Rapport Final Août',
                    labelText: 'Nouveau nom',
                  ),
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, null),
                    child: const Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, controller.text),
                    child: const Text('Enregistrer'),
                  ),
                ],
              );
            },
          );

          if (newName != null && mounted) {
            await FirebaseFirestore.instance.collection('rapports').doc(docId).update({
              'nomPersonnalise': newName,
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rapport renommé avec succès'),
                backgroundColor: Colors.green,
              ),
            );
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Action impossible : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Formatage de la période ──
  String _formatPeriode(Map<String, dynamic> data) {
    final debut = (data['debut'] as Timestamp?)?.toDate();
    final fin = (data['fin'] as Timestamp?)?.toDate();
    if (debut == null || fin == null) return '';
    final finAffichage = fin.subtract(const Duration(days: 1));
    return 'du ${debut.day.toString().padLeft(2, '0')}/${debut.month.toString().padLeft(2, '0')}'
        ' au ${finAffichage.day.toString().padLeft(2, '0')}/${finAffichage.month.toString().padLeft(2, '0')}/${finAffichage.year}';
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('rapports')
        .snapshots();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text(
          'Rapports hebdomadaires',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Tooltip(
            message: 'Envoyer résumé par mail',
            child: IconButton(
              icon: _isSendingEmail
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.email_outlined, color: Colors.white),
              onPressed: _isSendingEmail ? null : _envoyerMail,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isGenerating ? null : _generateReport,
        backgroundColor: const Color(0xFF1A73E8),
        icon: _isGenerating
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add, color: Colors.white),
        label: Text(
          _isGenerating ? 'Génération…' : 'Générer le rapport',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          if (_isGenerating)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '⏳ Génération du rapport en cours… Veuillez conserver cette fenêtre ouverte.',
                      style: TextStyle(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final docs = (snapshot.data?.docs ?? []).toList()
            ..sort((a, b) {
              final aDate = (a.data()['createdAt'] as Timestamp?)?.toDate() ??
                  (a.data()['debut'] as Timestamp?)?.toDate() ??
                  DateTime(2000);
              final bDate = (b.data()['createdAt'] as Timestamp?)?.toDate() ??
                  (b.data()['debut'] as Timestamp?)?.toDate() ??
                  DateTime(2000);
              return bDate.compareTo(aDate);
            });

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text(
                    'Aucun rapport généré.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Appuyez sur "Générer le rapport" pour créer le premier rapport.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final semaine = data['semaine'];
              final annee = data['annee'];
              final excelUrl = data['excelUrl'] as String?;
              final pdfUrl = data['pdfUrl'] as String?;
              final nomPersonnalise = data['nomPersonnalise'] as String?;
              final bool hasExcel = excelUrl != null && excelUrl.isNotEmpty;
              final bool hasPdf = pdfUrl != null && pdfUrl.isNotEmpty;
              final String periode = _formatPeriode(data);
              
              final String titreAffiche = (nomPersonnalise != null && nomPersonnalise.trim().isNotEmpty) 
                  ? nomPersonnalise 
                  : 'Semaine $semaine — $annee';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A73E8).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder_copy_rounded,
                      color: Color(0xFF1A73E8),
                    ),
                  ),
                  title: Text(
                    titreAffiche,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (nomPersonnalise != null && nomPersonnalise.trim().isNotEmpty)
                        Text('Semaine $semaine — $annee', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      if (periode.isNotEmpty)
                        Text(periode,
                            style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _badge(
                            hasExcel ? 'Excel ✓' : 'Excel —',
                            hasExcel ? Colors.green : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          _badge(
                            hasPdf ? 'PDF ✓' : 'PDF —',
                            hasPdf ? Colors.red : Colors.grey,
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (type) => _action(type, data, docs[index].id),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'viewPdf',
                        child: ListTile(
                          leading: Icon(Icons.picture_as_pdf_outlined,
                              color: Colors.red),
                          title: Text('Voir le PDF'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'downloadPdf',
                        child: ListTile(
                          leading: Icon(Icons.download_outlined,
                              color: Colors.red),
                          title: Text('Télécharger PDF'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'viewExcel',
                        child: ListTile(
                          leading: Icon(Icons.table_chart_outlined,
                              color: Colors.green),
                          title: Text('Voir Excel'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'downloadExcel',
                        child: ListTile(
                          leading: Icon(Icons.download_outlined,
                              color: Colors.green),
                          title: Text('Télécharger Excel'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'shareAll',
                        child: ListTile(
                          leading: Icon(Icons.share_outlined,
                              color: Color(0xFF1A73E8)),
                          title: Text('Partager Excel + PDF'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined,
                              color: Colors.orange),
                          title: Text('Renommer le rapport'),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline,
                              color: Colors.red),
                          title: Text('Supprimer',
                              style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  ],
),
);
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
