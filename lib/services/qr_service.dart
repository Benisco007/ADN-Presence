import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QrService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Vérifier si le QR Code scanné est valide
  Future<QrVerificationResult> verifierQrCode(String qrCodeScanne) async {
    try {
      // 1. Récupérer le parcId de l'employé connecté
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
      final tablettDoc =
          await _firestore.collection('tablettes').doc(parcId).get();
      if (!tablettDoc.exists) {
        return QrVerificationResult.erreur(
            'Aucune tablette configurée pour votre parc.');
      }

      final qrCodeDuJour =
          tablettDoc.data()?['qrCodeDuJour'] as String?;
      if (qrCodeDuJour == null || qrCodeDuJour.isEmpty) {
        return QrVerificationResult.erreur(
            'QR Code du jour non disponible.');
      }

      // 3. Vérifier que le QR Code scanné correspond au QR Code du jour
      if (qrCodeScanne != qrCodeDuJour) {
        return QrVerificationResult.erreur(
            'QR Code invalide ou expiré.');
      }

      // 4. Vérifier que la date encodée dans le QR Code est bien aujourd'hui
      // Format attendu : ADN_{PARC_ID}_{DATE}_{SECRET}
      final parties = qrCodeScanne.split('_');
      if (parties.length < 4) {
        return QrVerificationResult.erreur('Format QR Code invalide.');
      }

      final dateEncodee = parties[2]; // YYYY-MM-DD
      final aujourdhui = DateTime.now();
      final dateAttendue =
          '${aujourdhui.year}-${aujourdhui.month.toString().padLeft(2, '0')}-${aujourdhui.day.toString().padLeft(2, '0')}';

      if (dateEncodee != dateAttendue) {
        return QrVerificationResult.erreur(
            'Ce QR Code n\'est pas valide pour aujourd\'hui.');
      }

      // ✅ Tout est bon
      return QrVerificationResult.succes();
    } catch (e) {
      return QrVerificationResult.erreur('Erreur inattendue : $e');
    }
  }
}

// Classe résultat de la vérification
class QrVerificationResult {
  final bool valide;
  final String? messageErreur;

  QrVerificationResult._({required this.valide, this.messageErreur});

  factory QrVerificationResult.succes() =>
      QrVerificationResult._(valide: true);

  factory QrVerificationResult.erreur(String message) =>
      QrVerificationResult._(valide: false, messageErreur: message);
}