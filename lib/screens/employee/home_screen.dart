import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/presence_service.dart';
import '../../services/location_service.dart';
import '../../services/auth_service.dart';
import '../../services/config_service.dart';
import '../auth/login_screen.dart';
import 'history_screen.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel currentUser;
  const HomeScreen({super.key, required this.currentUser});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PresenceService _presenceService = PresenceService();
  final LocationService _locationService = LocationService();
  final AuthService _authService = AuthService();
  final ConfigService _configService = ConfigService();

  bool _dejaMarque = false;
  bool _isLoading = false;
  String _message = '';
  Color _messageColor = Colors.green;

  @override
  void initState() {
    super.initState();
    _verifierPresence();
  }

  Future<void> _verifierPresence() async {
    bool marque = await _presenceService.dejaMarqueAujourdhui();
    if (mounted) {
      setState(() => _dejaMarque = marque);
    }
  }

  Future<void> _marquerPresenceManuellement() async {
    setState(() {
      _isLoading = true;
      _message = 'Vérification de votre position...';
      _messageColor = Colors.blue;
    });

    bool dejaMarque = await _presenceService.dejaMarqueAujourdhui();
    if (dejaMarque) {
      setState(() {
        _isLoading = false;
        _dejaMarque = true;
        _message = 'Vous avez déjà marqué votre présence aujourd\'hui.';
        _messageColor = Colors.orange;
      });
      return;
    }

    bool auBureau = await _locationService.estAuBureau();
    if (!auBureau) {
      setState(() {
        _isLoading = false;
        _message =
            'Marquage refusé : vous n\'êtes pas dans la zone du bureau (WiFi ou GPS).';
        _messageColor = Colors.red;
      });
      return;
    }

    bool succes = await _presenceService.marquerPresence('manuel');

    setState(() {
      _isLoading = false;
      if (succes) {
        _dejaMarque = true;
        _message = 'Présence marquée manuellement ✅';
        _messageColor = Colors.green;
      } else {
        _message = 'Erreur lors du marquage.';
        _messageColor = Colors.red;
      }
    });
  }

  Future<void> _marquerPresenceAuto() async {
    setState(() {
      _isLoading = true;
      _message = 'Vérification de votre position...';
      _messageColor = Colors.blue;
    });

    bool dejaMarque = await _presenceService.dejaMarqueAujourdhui();
    if (dejaMarque) {
      setState(() {
        _isLoading = false;
        _dejaMarque = true;
        _message = 'Vous avez déjà marqué votre présence aujourd\'hui.';
        _messageColor = Colors.orange;
      });
      return;
    }

    bool auBureau = await _locationService.estAuBureau();

    if (auBureau) {
      bool succes = await _presenceService.marquerPresence('automatique');
      setState(() {
        _isLoading = false;
        if (succes) {
          _dejaMarque = true;
          _message = 'Présence automatique marquée ✅';
          _messageColor = Colors.green;
        } else {
          _message = 'Erreur lors du marquage.';
          _messageColor = Colors.red;
        }
      });
    } else {
      setState(() {
        _isLoading = false;
        _message = 'Vous n\'êtes pas dans la zone du bureau.';
        _messageColor = Colors.red;
      });
    }
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

  // ── Interface Mode WiFi/GPS (Phase 1 conservée) ──
  Widget _interfaceWifiGps() {
    return Column(
      children: [
        // Bouton marquage automatique
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton.icon(
            onPressed:
                (_isLoading || _dejaMarque) ? null : _marquerPresenceAuto,
            icon: const Icon(Icons.location_on),
            label: const Text(
              'Marquer ma présence (Auto)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A73E8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Bouton marquage manuel
        SizedBox(
          width: double.infinity,
          height: 55,
          child: OutlinedButton.icon(
            onPressed: (_isLoading || _dejaMarque)
                ? null
                : _marquerPresenceManuellement,
            icon: const Icon(Icons.edit),
            label: const Text(
              'Marquage manuel (secours)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Interface Mode QR Code (Phase 2) ──
  Widget _interfaceQrCode() {
    return Column(
      children: [
        // Explication visuelle
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.purple, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Votre parc utilise le mode QR Code. Scannez la tablette à l\'entrée pour pointer.',
                  style: TextStyle(color: Colors.purple, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Bouton scanner QR Code
        SizedBox(
          width: double.infinity,
          height: 60,
          child: ElevatedButton.icon(
            onPressed: (_isLoading || _dejaMarque)
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const QrScannerScreen(),
                      ),
                    );
                    // Rafraîchir le statut après retour du scanner
                    await _verifierPresence();
                  },
            icon: const Icon(Icons.qr_code_scanner, size: 28),
            label: const Text(
              'Scanner le QR Code',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final parcId = widget.currentUser.parcId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text('ADN Presence',
            style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _deconnexion,
          ),
        ],
      ),
      body: StreamBuilder<String>(
        stream: _configService.ecouterMode(parcId),
        builder: (context, modeSnapshot) {
          final mode = modeSnapshot.data ?? 'wifi_gps';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Carte de bienvenue ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: mode == 'qr_code'
                        ? Colors.purple
                        : const Color(0xFF1A73E8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bonjour ${widget.currentUser.prenom} 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.currentUser.poste,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              _dejaMarque ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _dejaMarque
                              ? '✅ Présent aujourd\'hui'
                              : '⏳ Pas encore marqué',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Message de retour ──
                if (_message.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: _messageColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _messageColor),
                    ),
                    child: Text(
                      _message,
                      style: TextStyle(
                          color: _messageColor,
                          fontWeight: FontWeight.w500),
                    ),
                  ),

                // ── Interface selon le mode ──
                if (mode == 'qr_code')
                  _interfaceQrCode()
                else
                  _interfaceWifiGps(),

                const SizedBox(height: 24),

                // ── Bouton historique (toujours visible) ──
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(
                              currentUser: widget.currentUser),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text(
                      'Voir mon historique',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}