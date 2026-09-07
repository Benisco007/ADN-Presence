import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../models/presence_model.dart';
import '../../services/presence_service.dart';

class HistoryScreen extends StatelessWidget {
  final UserModel currentUser;
  const HistoryScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final PresenceService presenceService = PresenceService();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text('Mon historique', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<PresenceModel>>(
        stream: presenceService.mesPresences(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'Aucune présence enregistrée.',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          List<PresenceModel> presences = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: presences.length,
            itemBuilder: (context, index) {
              PresenceModel p = presences[index];
              bool estAuto = p.type == 'automatique';

              String heure =
                  '${p.heureArrivee.hour}h${p.heureArrivee.minute.toString().padLeft(2, '0')}';
              String date =
                  '${p.date.day}/${p.date.month}/${p.date.year}';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration: BoxDecoration(
                        color: estAuto
                            ? Colors.green.shade50
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        estAuto ? Icons.location_on : Icons.edit,
                        color: estAuto ? Colors.green : Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            date,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Arrivée : $heure',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: estAuto
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        estAuto ? 'Auto' : 'Manuel',
                        style: TextStyle(
                          color: estAuto ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
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
}