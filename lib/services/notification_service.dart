import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service pour créer des notifications internes dans Firestore
/// (collection /notifications — lues par les admins dans le dashboard)
class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Crée une notification admin dans Firestore
  Future<void> creerNotificationAdmin({
    required String message,
    String? adminId,
  }) async {
    try {
      final uid = adminId ?? _auth.currentUser?.uid;
      if (uid == null) return;

      await _firestore.collection('notifications').add({
        'message': message,
        'date': FieldValue.serverTimestamp(),
        'lu': false,
        'adminId': uid,
      });
    } catch (e) {
      // Silencieux — ne pas bloquer le flux principal
    }
  }

  /// Stream des notifications non lues pour un admin
  Stream<QuerySnapshot> ecouterNotificationsNonLues(String adminId) {
    return _firestore
        .collection('notifications')
        .where('adminId', isEqualTo: adminId)
        .where('lu', isEqualTo: false)
        .orderBy('date', descending: true)
        .snapshots();
  }

  /// Marquer une notification comme lue
  Future<void> marquerCommeLue(String notificationId) async {
    await _firestore
        .collection('notifications')
        .doc(notificationId)
        .update({'lu': true});
  }
}
