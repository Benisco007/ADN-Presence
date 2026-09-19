import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/qr_service.dart';
import '../../services/presence_service.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  final QrService _qrService = QrService();
  final PresenceService _presenceService = PresenceService();
  final MobileScannerController _cameraController = MobileScannerController();

  late AnimationController _animationController;
  late Animation<double> _scanAnimation;

  bool _enTraitement = false;
  bool _scanTermine = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
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
        message: 'Erreur lors du marquage. Réessayer.',
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
          if (!kIsWeb)
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

          // ── Overlay de visée animé professionnel ──
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _scanAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: ScannerOverlayPainter(
                    borderColor: const Color(0xFFAB47BC),
                    borderRadius: 18,
                    borderLength: 36,
                    borderWidth: 4.5,
                    scanLinePosition: _scanAnimation.value,
                  ),
                );
              },
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
                  const CircularProgressIndicator(color: Color(0xFFAB47BC))
                else
                  const Icon(
                    Icons.qr_code_scanner,
                    color: Colors.white70,
                    size: 36,
                  ),
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

          // ── Saisie manuelle (Fallback Web) ──
          if (kIsWeb)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Saisir le code manuellement',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (value) {
                          if (value.isNotEmpty) _traiterQrCode(value);
                        },
                      ),
                    ),
                    const Icon(Icons.keyboard_return, color: Colors.grey),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── CustomPainter pour le viseur scanner haut de gamme avec laser animé ──
class ScannerOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double borderRadius;
  final double borderLength;
  final double borderWidth;
  final double scanLinePosition;

  ScannerOverlayPainter({
    required this.borderColor,
    required this.borderRadius,
    required this.borderLength,
    required this.borderWidth,
    required this.scanLinePosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = size.width * 0.70;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 30),
      width: scanSize,
      height: scanSize,
    );
    final rrect = RRect.fromRectAndRadius(scanRect, Radius.circular(borderRadius));

    // 1. Masque sombre extérieur
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(rrect);
    final overlayPath = Path.combine(PathOperation.difference, backgroundPath, cutoutPath);

    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    canvas.drawPath(overlayPath, overlayPaint);

    // 2. Fine bordure de cadrage guide
    final guideBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(rrect, guideBorderPaint);

    // 3. Dessin du laser de balayage animé (délimité à l'intérieur du cadre)
    canvas.save();
    canvas.clipRRect(rrect);

    final currentY = scanRect.top + (scanRect.height * scanLinePosition);

    // Faisceau d'ombrage du laser
    const beamHeight = 45.0;
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          borderColor.withValues(alpha: 0.0),
          borderColor.withValues(alpha: 0.28),
          borderColor.withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromLTRB(
          scanRect.left,
          currentY - beamHeight / 2,
          scanRect.right,
          currentY + beamHeight / 2,
        ),
      );

    canvas.drawRect(
      Rect.fromLTRB(
        scanRect.left,
        currentY - beamHeight / 2,
        scanRect.right,
        currentY + beamHeight / 2,
      ),
      beamPaint,
    );

    // Ligne principale filigrane lumineuse
    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          borderColor.withValues(alpha: 0.05),
          const Color(0xFFE1BEE7),
          Colors.white,
          const Color(0xFFE1BEE7),
          borderColor.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(
        Rect.fromLTWH(scanRect.left, currentY - 1.5, scanRect.width, 3),
      )
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(scanRect.left + 4, currentY),
      Offset(scanRect.right - 4, currentY),
      linePaint,
    );

    canvas.restore();

    // 4. Dessin des 4 coins d'angle arrondis (tracés correctement vers l'extérieur)
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    final left = scanRect.left;
    final right = scanRect.right;
    final top = scanRect.top;
    final bottom = scanRect.bottom;
    final r = borderRadius;
    final l = borderLength;

    // Coin Haut-Gauche
    final topLeftPath = Path()
      ..moveTo(left, top + l)
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r), clockwise: true)
      ..lineTo(left + l, top);
    canvas.drawPath(topLeftPath, cornerPaint);

    // Coin Haut-Droit
    final topRightPath = Path()
      ..moveTo(right - l, top)
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r), clockwise: true)
      ..lineTo(right, top + l);
    canvas.drawPath(topRightPath, cornerPaint);

    // Coin Bas-Droit
    final bottomRightPath = Path()
      ..moveTo(right, bottom - l)
      ..lineTo(right, bottom - r)
      ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r), clockwise: true)
      ..lineTo(right - l, bottom);
    canvas.drawPath(bottomRightPath, cornerPaint);

    // Coin Bas-Gauche
    final bottomLeftPath = Path()
      ..moveTo(left + l, bottom)
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r), clockwise: true)
      ..lineTo(left, bottom - l);
    canvas.drawPath(bottomLeftPath, cornerPaint);
  }

  @override
  bool shouldRepaint(covariant ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanLinePosition != scanLinePosition ||
        oldDelegate.borderColor != borderColor;
  }
}