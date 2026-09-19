import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'dashboard_screen.dart';
import 'employees_screen.dart';
import 'history_admin_screen.dart';
import 'parks_screen.dart';
import 'reports_screen.dart';
import 'security_screen.dart';
import '../common/help_center_screen.dart';

class WebAdminLayout extends StatefulWidget {
  final UserModel currentUser;
  
  const WebAdminLayout({super.key, required this.currentUser});

  @override
  State<WebAdminLayout> createState() => _WebAdminLayoutState();
}

class _WebAdminLayoutState extends State<WebAdminLayout> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      DashboardScreen(currentUser: widget.currentUser),
      const EmployeesScreen(),
      const ParksScreen(),
      const ReportsScreen(),
      const HistoryAdminScreen(),
      const HelpCenterScreen(isAdmin: true),
      const SecurityScreen(),
    ];
  }

  Future<void> _deconnexion() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (!isDesktop) {
      // Mobile fallback: use standard dashboard
      return DashboardScreen(currentUser: widget.currentUser);
    }

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            color: Colors.white,
            child: Column(
              children: [
                UserAccountsDrawerHeader(
                  accountName: Text('${widget.currentUser.prenom} ${widget.currentUser.nom}'),
                  accountEmail: const Text('Administrateur'),
                  currentAccountPicture: const CircleAvatar(
                    child: Icon(Icons.admin_panel_settings),
                  ),
                  decoration: const BoxDecoration(color: Color(0xFF1A73E8)),
                  margin: EdgeInsets.zero,
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildNavItem(Icons.dashboard, 'Tableau de bord', 0),
                      _buildNavItem(Icons.people, 'Employés', 1),
                      _buildNavItem(Icons.location_city, 'Parcs', 2),
                      const Divider(),
                      _buildNavItem(Icons.folder_copy, 'Rapports', 3),
                      _buildNavItem(Icons.history, 'Historique', 4),
                      const Divider(),
                      _buildNavItem(Icons.help_outline, 'Aide & FAQ', 5),
                      _buildNavItem(Icons.security, 'Sécurité', 6),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
                  onTap: _deconnexion,
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          // Contenu principal
          Expanded(
            child: _pages[_selectedIndex],
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String title, int index) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFF1A73E8) : Colors.grey[700]),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFF1A73E8) : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFF1A73E8).withOpacity(0.1),
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
    );
  }
}
