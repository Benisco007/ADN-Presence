import 'package:cloud_firestore/cloud_firestore.dart';

class ConfigService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Lire le mode en temps réel pour un parc donné
  Stream<String> ecouterMode(String parcId) {
    return _firestore
        .collection('config')
        .doc(parcId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return 'wifi_gps';
          return doc.data()!['modeMarquage'] as String? ?? 'wifi_gps';
        });
  }

  // Changer le mode (appelé par l'admin)
  Future<void> changerMode(String parcId, String mode) async {
    await _firestore.collection('config').doc(parcId).set(
      {'modeMarquage': mode},
      SetOptions(merge: true),
    );
  }

  // Lire le mode une seule fois (sans stream)
  Future<String> lireMode(String parcId) async {
    final doc = await _firestore.collection('config').doc(parcId).get();
    if (!doc.exists || doc.data() == null) return 'wifi_gps';
    return doc.data()!['modeMarquage'] as String? ?? 'wifi_gps';
  }
}