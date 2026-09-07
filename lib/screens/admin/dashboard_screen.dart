import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../models/presence_model.dart';
import '../../services/auth_service.dart';
import '../../services/presence_service.dart';
import '../auth/login_screen.dart';
import 'employees_screen.dart';
import 'history_admin_screen.dart';
import 'parks_screen.dart';
import 'reports_screen.dart';

class DashboardScreen extends StatefulWidget {
  final UserModel currentUser;
  const DashboardScreen({super.key, required this.currentUser});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();
  final PresenceService _presenceService = PresenceService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _deconnexion() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  String _dateAujourdhui() {
    DateTime now = DateTime.now();
    List<String> mois = [
      'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
    ];
    return '${now.day} ${mois[now.month - 1]} ${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text('Dashboard Admin', style: TextStyle(color: Colors.white)),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                accountName: Text('${widget.currentUser.prenom} ${widget.currentUser.nom}'),
                accountEmail: const Text('Administrateur'),
                currentAccountPicture: const CircleAvatar(
                  child: Icon(Icons.admin_panel_settings),
                ),
                decoration: const BoxDecoration(color: Color(0xFF1A73E8)),
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Employés'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const EmployeesScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.location_city),
                title: const Text('Parcs'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ParksScreen()));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.folder_copy),
                title: const Text('Rapports hebdomadaires'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Historique des présences'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryAdminScreen()));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Déconnexion'),
                onTap: _deconnexion,
              ),
            ],
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF1A73E8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bonjour ${widget.currentUser.prenom} 👋',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Présences du ${_dateAujourdhui()}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // Compteurs
          StreamBuilder<List<PresenceModel>>(
            stream: _presenceService.toutesLesPresences(),
            builder: (context, snapshot) {
              int presents = 0;
              int manuels = 0;

              if (snapshot.hasData) {
                DateTime aujourd = DateTime.now();
                List<PresenceModel> aujourdhui = snapshot.data!.where((p) {
                  return p.date.year == aujourd.year &&
                      p.date.month == aujourd.month &&
                      p.date.day == aujourd.day;
                }).toList();

                presents = aujourdhui.length;
                manuels = aujourdhui.where((p) => p.type == 'manuel').length;
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _carteCompteur('Présents', presents.toString(), Colors.green, Icons.check_circle),
                    const SizedBox(width: 12),
                    _carteCompteur('Manuels', manuels.toString(), Colors.orange, Icons.edit),
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('users')
                  .where('role', isEqualTo: 'employe')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Aucun employé enregistré.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                List<UserModel> employes = snapshot.data!.docs
                    .map((doc) => UserModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                    .toList();

                return StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                      .collection('parcs')
                      .where('adminId', isEqualTo: widget.currentUser.id)
                      .snapshots(),
                  builder: (context, parksSnapshot) {
                    final parks = parksSnapshot.data?.docs
                            .map((doc) => {
                                  'id': doc.id,
                                  'nom': (doc.data() as Map<String, dynamic>)['nom'] ?? 'Parc sans nom',
                                })
                            .toList() ??
                        [];
                    final grouped = <String, List<UserModel>>{};
                    for (final employee in employes) {
                      grouped.putIfAbsent(employee.parcId ?? '', () => []).add(employee);
                    }

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

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: parks.length + (grouped['']?.isNotEmpty == true ? 1 : 0),
                      itemBuilder: (context, index) {
                        final hasUnassigned = grouped['']?.isNotEmpty == true;
                        final isUnassignedCard = hasUnassigned && index == parks.length;
                        final parkId = isUnassignedCard ? '' : parks[index]['id'] as String;
                        final parkName = isUnassignedCard
                            ? 'Employés sans parc'
                            : parks[index]['nom'] as String;
                        final parkEmployees = grouped[parkId] ?? [];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ExpansionTile(
                            leading: const Icon(Icons.location_city),
                            title: Text(parkName),
                            subtitle: Text('${parkEmployees.length} employé(s)'),
                            children: parkEmployees
                                .map((employee) => _employeeTile(employee, presencesAujourdhui))
                                .toList(),
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
          ),
        ],
      ),
    );
  }

  Widget _employeeTile(
    UserModel employe,
    List<PresenceModel> presencesAujourdhui,
  ) {
    PresenceModel? presence;
    for (final item in presencesAujourdhui) {
      if (item.userId == employe.id) {
        presence = item;
        break;
      }
    }

    var couleur = Colors.red;
    var statut = 'Absent';
    var icone = Icons.cancel;
    if (presence != null) {
      couleur = presence.type == 'automatique' ? Colors.green : Colors.orange;
      statut = presence.type == 'automatique' ? 'Présent' : 'Manuel';
      icone = presence.type == 'automatique' ? Icons.check_circle : Icons.edit;
    }

    return ListTile(
      leading: CircleAvatar(
        child: Text(employe.prenom.isEmpty ? '?' : employe.prenom[0].toUpperCase()),
      ),
      title: Text('${employe.prenom} ${employe.nom}'),
      subtitle: Text(employe.poste),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: couleur, size: 16),
          const SizedBox(width: 4),
          Text(statut, style: TextStyle(color: couleur, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _carteCompteur(String titre, String valeur, Color couleur, IconData icone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: couleur.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: couleur.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icone, color: couleur, size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  valeur,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: couleur,
                  ),
                ),
                Text(titre, style: TextStyle(color: couleur, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}