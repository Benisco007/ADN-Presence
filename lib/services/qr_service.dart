import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'location_service.dart';

class QrService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocationService _locationService = LocationService();

  Future<QrVerificationResult> verifierQrCode(String qrCodeScanne) async {
    try {
      // 1. Récupérer le parcId de l'employé
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        return QrVerificationResult.erreur('Utilisateur non connecté.');
      }

      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return QrVerificationResult.erreur('Profil introuvable.');
      }

      final parcId = userDoc.data()?['parcId'] as String?;
      if (parcId == null || parcId.isEmpty) {
        return QrVerificationResult.erreur(
            'Vous n\'êtes affecté à aucun parc.');
      }

      // 2. Récupérer le QR Code du jour depuis Firestore
      final tabletteDoc =
          await _firestore.collection('tablettes').doc(parcId).get();
      if (!tabletteDoc.exists) {
        return QrVerificationResult.erreur(
            'Aucune tablette configurée pour votre parc.');
      }

      final qrCodeDuJour = tabletteDoc.data()?['qrCodeDuJour'] as String?;
      if (qrCodeDuJour == null || qrCodeDuJour.isEmpty) {
        return QrVerificationResult.erreur('QR Code du jour non disponible.');
      }

      // 3. Vérifier que le QR Code scanné = QR Code du jour
      if (qrCodeScanne.trim() != qrCodeDuJour.trim()) {
        return QrVerificationResult.erreur('QR Code invalide ou expiré.');
      }

      // 4. ✅ NOUVEAU — Vérifier que l'employé est physiquement dans la zone
      final bool auBureau = await _locationService.estAuBureau();
      if (!auBureau) {
        return QrVerificationResult.erreur(
            'QR Code valide mais vous n\'êtes pas détecté dans la zone du parc.\n'
            'Connectez-vous au WiFi du parc ou soyez dans le périmètre.');
      }

      // ✅ Tout est bon — QR Code + présence physique confirmés
      return QrVerificationResult.succes();
    } catch (e) {
      return QrVerificationResult.erreur('Erreur inattendue : $e');
    }
  }
}

class QrVerificationResult {
  final bool valide;
  final String? messageErreur;

  QrVerificationResult._({required this.valide, this.messageErreur});

  factory QrVerificationResult.succes() =>
      QrVerificationResult._(valide: true);

  factory QrVerificationResult.erreur(String message) =>
      QrVerificationResult._(valide: false, messageErreur: message);
}