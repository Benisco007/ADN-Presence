import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../models/presence_model.dart';
import '../../services/presence_service.dart';
import '../../widgets/contextual_help_button.dart';

class ParkDetailScreen extends StatefulWidget {
  final String parkId;
  final String parkName;

  const ParkDetailScreen({
    super.key,
    required this.parkId,
    required this.parkName,
  });

  @override
  State<ParkDetailScreen> createState() => _ParkDetailScreenState();
}

class _ParkDetailScreenState extends State<ParkDetailScreen> {
  final PresenceService _presenceService = PresenceService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _formatHeure(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
  }

  String _dateAujourdhui() {
    DateTime now = DateTime.now();
    List<String> mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return '${now.day} ${mois[now.month - 1]} ${now.year}';
  }

  // ── Dialogue correction heure d'arrivée ──
  Future<void> _corrigerHeure(PresenceModel presence, UserModel employe) async {
    TimeOfDay heureActuelle = TimeOfDay(
      hour: presence.heureArrivee.hour,
      minute: presence.heureArrivee.minute,
    );

    final TimeOfDay? nouvelleHeure = await showTimePicker(
      context: context,
      initialTime: heureActuelle,
      helpText: 'Corriger l\'heure d\'arrivée de ${employe.prenom}',
      confirmText: 'Confirmer',
      cancelText: 'Annuler',
    );

    if (nouvelleHeure == null || !mounted) return;

    final DateTime heureCorrigee = DateTime(
      presence.heureArrivee.year,
      presence.heureArrivee.month,
      presence.heureArrivee.day,
      nouvelleHeure.hour,
      nouvelleHeure.minute,
    );

    try {
      await _firestore.collection('presences').doc(presence.id).update({
        'heureArrivee': Timestamp.fromDate(heureCorrigee),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Heure d\'arrivée de ${employe.prenom} corrigée à ${_formatHeure(heureCorrigee)}',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la correction de l\'heure.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: Text(
          widget.parkName,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: const [
          ContextualHelpButton(
            title: 'Détails des présences du parc',
            description:
                'Cet écran liste tous les employés affectés à ce parc et leurs activités du jour.\n\n- Vous voyez leur heure d\'arrivée.\n- Les sorties temporaires et retours (pauses).\n- Le total d\'heures supplémentaires de chaque employé.',
            tips: [
              'Appuyez sur l\'icône de crayon bleu pour corriger l\'heure d\'arrivée d\'un employé si nécessaire.',
            ],
            iconColor: Colors.white,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .where('role', isEqualTo: 'employe')
            .snapshots(),
        builder: (context, usersSnapshot) {
          if (usersSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allEmployees = usersSnapshot.data?.docs
                  .map((doc) => UserModel.fromMap(
                      doc.id, doc.data() as Map<String, dynamic>))
                  .toList() ??
              [];

          // Filtrer les employés du parc
          final parkEmployees = allEmployees.where((emp) {
            if (widget.parkId.isEmpty) {
              return emp.parcId == null || emp.parcId!.isEmpty;
            }
            return emp.parcId == widget.parkId;
          }).toList();

          return StreamBuilder<List<PresenceModel>>(
            stream: _presenceService.toutesLesPresences(),
            builder: (context, presenceSnapshot) {
              List<PresenceModel> presencesAujourdhui = [];
              if (presenceSnapshot.hasData) {
                DateTime aujourd = DateTime.now();
                presencesAujourdhui = presenceSnapshot.data!.where((p) {
                  return p.date.year == aujourd.year &&
                      p.date.month == aujourd.month &&
                      p.date.day == aujourd.day;
                }).toList();
              }

              // Compteurs
              int presentsCount = 0;
              for (var emp in parkEmployees) {
                if (presencesAujourdhui.any((p) => p.userId == emp.id)) {
                  presentsCount++;
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Carte En-tête Parc ──
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A73E8).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.location_city,
                                    color: Color(0xFF1A73E8),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.parkName,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Présences du ${_dateAujourdhui()}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _statChip(
                                  'Total employés',
                                  parkEmployees.length.toString(),
                                  Colors.blue,
                                ),
                                _statChip(
                                  'Présents',
                                  presentsCount.toString(),
                                  Colors.green,
                                ),
                                _statChip(
                                  'Absents',
                                  (parkEmployees.length - presentsCount).toString(),
                                  Colors.red,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Liste des Employés',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (parkEmployees.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'Aucun employé affecté à ce parc.',
                            style: TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: parkEmployees.length,
                        itemBuilder: (context, index) {
                          final employe = parkEmployees[index];
                          final presence = presencesAujourdhui.firstWhere(
                            (p) => p.userId == employe.id,
                            orElse: () => PresenceModel(
                              id: '',
                              userId: '',
                              date: DateTime.now(),
                              heureArrivee: DateTime.now(),
                              type: 'absent',
                              statut: 'absent',
                            ),
                          );
                          final isPresent = presence.id.isNotEmpty;

                          return _employeeDetailCard(employe, presence, isPresent);
                        },
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _statChip(String label, String count, Color color) {
    return Column(
      children: [
        Text(
          count,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _employeeDetailCard(
    UserModel employe,
    PresenceModel presence,
    bool isPresent,
  ) {
    Color statusColor = Colors.red;
    String statusText = 'Absent';
    IconData statusIcon = Icons.cancel;

    if (isPresent) {
      if (presence.type == 'automatique') {
        statusColor = Colors.green;
        statusText = '✅ Automatique';
        statusIcon = Icons.check_circle;
      } else if (presence.type == 'qr_code') {
        statusColor = Colors.purple;
        statusText = '🟣 QR Code';
        statusIcon = Icons.qr_code;
      } else {
        statusColor = Colors.orange;
        statusText = '🟠 Manuel';
        statusIcon = Icons.edit;
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ligne 1 : Avatar, Nom, Poste, Statut
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Text(
                    employe.prenom.isEmpty ? '?' : employe.prenom[0].toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${employe.prenom} ${employe.nom}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        employe.poste.isEmpty ? 'Employé' : employe.poste,
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (isPresent) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Grille d'informations : Arrivée, Sorties/Retours, Heures Sup
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Box 1 : Heure d'arrivée
                  Expanded(
                    child: _infoBox(
                      icon: Icons.login,
                      iconColor: Colors.green,
                      title: 'Arrivée',
                      value: _formatHeure(presence.heureArrivee),
                      action: IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                        tooltip: 'Corriger l\'heure d\'arrivée',
                        onPressed: () => _corrigerHeure(presence, employe),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Box 2 : Heures supplémentaires
                  Expanded(
                    child: _infoBox(
                      icon: Icons.more_time,
                      iconColor: Colors.purple,
                      title: 'Heures Sup',
                      value: presence.heuresSupplementaires > 0
                          ? '+${presence.heuresSupplementaires} min'
                          : '0 min',
                    ),
                  ),
                ],
              ),

              // Section Mouvements (Sorties / Retours)
              if (presence.mouvements.isNotEmpty || presence.heureSortieDefinitive != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.directions_walk, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            'Sorties & Retours du jour :',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...presence.mouvements.map((m) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '• Sortie : ${_formatHeure(m.sortie)}${m.retour != null ? ' ➔ Retour : ${_formatHeure(m.retour!)}' : ' (En cours...)'}',
                            style: TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        );
                      }),
                      if (presence.heureSortieDefinitive != null)
                        Text(
                          '• Sortie définitive : ${_formatHeure(presence.heureSortieDefinitive!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoBox({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }
}
