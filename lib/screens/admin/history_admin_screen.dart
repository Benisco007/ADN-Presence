import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/presence_model.dart';
import '../../models/user_model.dart';

class HistoryAdminScreen extends StatelessWidget {
  const HistoryAdminScreen({super.key});

  Future<void> _modifierHeure(
      BuildContext context, PresenceModel presence) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(presence.heureArrivee),
    );
    if (time == null) return;

    final heure = DateTime(
      presence.heureArrivee.year,
      presence.heureArrivee.month,
      presence.heureArrivee.day,
      time.hour,
      time.minute,
    );
    try {
      await FirebaseFirestore.instance
          .collection('presences')
          .doc(presence.id)
          .update({'heureArrivee': Timestamp.fromDate(heure)});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Heure de présence modifiée avec succès.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Modification impossible : ${error.code}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text('Historique global',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('presences')
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, presenceSnap) {
          if (presenceSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!presenceSnap.hasData || presenceSnap.data!.docs.isEmpty) {
            return const Center(child: Text('Aucune présence enregistrée.'));
          }

          final List<PresenceModel> presences = presenceSnap.data!.docs
              .map((doc) =>
                  PresenceModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();

          // Utilisateurs
          return StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('users').snapshots(),
            builder: (context, userSnap) {
              final Map<String, UserModel> users = {};
              if (userSnap.hasData) {
                for (final doc in userSnap.data!.docs) {
                  users[doc.id] = UserModel.fromMap(
                      doc.id, doc.data() as Map<String, dynamic>);
                }
              }

              // Parcs
              return StreamBuilder<QuerySnapshot>(
                stream: firestore.collection('parcs').snapshots(),
                builder: (context, parcSnap) {
                  final Map<String, String> parcs = {};
                  if (parcSnap.hasData) {
                    for (final doc in parcSnap.data!.docs) {
                      final d = doc.data() as Map<String, dynamic>;
                      parcs[doc.id] = (d['nom'] as String?) ?? 'Parc sans nom';
                    }
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: presences.length,
                    itemBuilder: (context, index) {
                      final PresenceModel p = presences[index];
                      final UserModel? user = users[p.userId];
                      final bool estAuto = p.type == 'automatique';
                      final String nomParc = user?.parcId != null
                          ? (parcs[user!.parcId] ?? 'Parc inconnu')
                          : 'Sans parc';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: estAuto
                                  ? Colors.green.shade50
                                  : Colors.orange.shade50,
                              child: Icon(
                                estAuto ? Icons.location_on : Icons.edit,
                                color:
                                    estAuto ? Colors.green : Colors.orange,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user != null
                                        ? '${user.prenom} ${user.nom}'
                                        : 'Employé inconnu',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '${p.date.day}/${p.date.month}/${p.date.year} — '
                                    '${p.heureArrivee.hour}h${p.heureArrivee.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                                  Text(
                                    nomParc,
                                    style: TextStyle(
                                        color: Colors.blue.shade400,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: estAuto
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                estAuto ? 'Auto' : 'Manuel',
                                style: TextStyle(
                                  color: estAuto
                                      ? Colors.green
                                      : Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_calendar),
                              tooltip: 'Modifier l\'heure',
                              onPressed: () => _modifierHeure(context, p),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}