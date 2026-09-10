import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/qr_service.dart';
import '../../services/presence_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final QrService _qrService = QrService();
  final PresenceService _presenceService = PresenceService();
  final MobileScannerController _cameraController = MobileScannerController();

  bool _enTraitement = false;
  bool _scanTermine = false;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _traiterQrCode(String qrCode) async {
    // Éviter les traitements multiples
    if (_enTraitement || _scanTermine) return;

    setState(() => _enTraitement = true);

    // Mettre la caméra en pause pendant le traitement
    await _cameraController.stop();

    // 1. Vérifier si déjà marqué
    final dejaMarque = await _presenceService.dejaMarqueAujourdhui();
    if (dejaMarque) {
      _afficherResultat(
        succes: false,
        message: 'Vous avez déjà marqué votre présence aujourd\'hui.',
        icone: Icons.info_outline,
        couleur: Colors.orange,
      );
      return;
    }

    // 2. Vérifier le QR Code
    final result = await _qrService.verifierQrCode(qrCode);

    if (!result.valide) {
      _afficherResultat(
        succes: false,
        message: result.messageErreur ?? 'QR Code invalide.',
        icone: Icons.error_outline,
        couleur: Colors.red,
      );
      return;
    }

    // 3. Marquer la présence
    final succes = await _presenceService.marquerPresence('qr_code');

    if (succes) {
      _afficherResultat(
        succes: true,
        message: 'Présence marquée avec succès ! ✅',
        icone: Icons.check_circle_outline,
        couleur: Colors.green,
      );
    } else {
      _afficherResultat(
        succes: false,
        message: 'Erreur lors du marquage. Réessayez.',
        icone: Icons.error_outline,
        couleur: Colors.red,
      );
    }
  }

  void _afficherResultat({
    required bool succes,
    required String message,
    required IconData icone,
    required Color couleur,
  }) {
    if (!mounted) return;

    setState(() {
      _enTraitement = false;
      _scanTermine = succes; // Si succès, on bloque les nouveaux scans
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: couleur, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: couleur,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(context); // Ferme le dialog
                if (succes) {
                  Navigator.pop(context); // Retourne à HomeScreen si succès
                } else {
                  // Relancer la caméra si échec
                  _cameraController.start();
                }
              },
              child: Text(
                succes ? 'Retour à l\'accueil' : 'Réessayer',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scanner le QR Code',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          // Bouton torche
          IconButton(
            icon: const Icon(Icons.flashlight_on, color: Colors.white),
            onPressed: () => _cameraController.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Caméra ──
          MobileScanner(
            controller: _cameraController,
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _traiterQrCode(barcode!.rawValue!);
              }
            },
          ),

          // ── Overlay de visée ──
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.purple, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Coins décoratifs
                  _coin(top: 0, left: 0),
                  _coin(top: 0, right: 0, flipH: true),
                  _coin(bottom: 0, left: 0, flipV: true),
                  _coin(bottom: 0, right: 0, flipH: true, flipV: true),
                ],
              ),
            ),
          ),

          // ── Texte d'instruction ──
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_enTraitement)
                  const CircularProgressIndicator(color: Colors.purple)
                else
                  const Icon(Icons.qr_code_scanner,
                      color: Colors.white54, size: 32),
                const SizedBox(height: 12),
                Text(
                  _enTraitement
                      ? 'Vérification en cours...'
                      : 'Pointez vers le QR Code de la tablette',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Coin décoratif du cadre de visée
  Widget _coin({
    double? top,
    double? bottom,
    double? left,
    double? right,
    bool flipH = false,
    bool flipV = false,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0),
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.purple, width: 4),
              left: BorderSide(color: Colors.purple, width: 4),
            ),
          ),
        ),
      ),
    );
  }
}