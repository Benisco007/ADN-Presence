import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/presence_model.dart';

class PresenceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Vérifier si déjà marqué aujourd'hui.
  // On filtre uniquement sur userId côté Firestore (pas d'index composite requis),
  // puis on compare les dates localement en Dart.
  Future<bool> dejaMarqueAujourdhui() async {
    final String uid = _auth.currentUser!.uid;
    final DateTime maintenant = DateTime.now();
    final DateTime debutJour = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    final DateTime finJour = debutJour.add(const Duration(days: 1));

    final QuerySnapshot snapshot = await _firestore
        .collection('presences')
        .where('userId', isEqualTo: uid)
        .get();

    // Filtrage local : on garde uniquement les documents dont
    // la date tombe dans la journée courante.
    final bool marqueAujourdhui = snapshot.docs.any((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final dateField = data['date'];
      if (dateField == null) return false;

      final DateTime datePresence = (dateField as Timestamp).toDate();
      return datePresence.isAfter(debutJour) &&
          datePresence.isBefore(finJour) ||
          datePresence.isAtSameMomentAs(debutJour);
    });

    return marqueAujourdhui;
  }

  // Marquer la présence
  Future<bool> marquerPresence(String type) async {
    try {
      bool dejaMarque = await dejaMarqueAujourdhui();
      if (dejaMarque) return false;

      String uid = _auth.currentUser!.uid;
      DateTime maintenant = DateTime.now();

      await _firestore.collection('presences').add({
        'userId': uid,
        'date': Timestamp.fromDate(maintenant),
        'heureArrivee': Timestamp.fromDate(maintenant),
        'type': type,
        'statut': 'present',
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // Récupérer les présences de l'utilisateur connecté
  Stream<List<PresenceModel>> mesPresences() {
    String uid = _auth.currentUser!.uid;
    return _firestore
        .collection('presences')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          List<PresenceModel> presences = snapshot.docs
              .map((doc) => PresenceModel.fromMap(doc.id, doc.data()))
              .toList();
          // Tri local par date décroissante
          presences.sort((a, b) => b.date.compareTo(a.date));
          return presences;
        });
  }

  // Récupérer toutes les présences (pour l'admin)
  Stream<List<PresenceModel>> toutesLesPresences() {
    return _firestore
        .collection('presences')
        .snapshots()
        .map((snapshot) {
          List<PresenceModel> presences = snapshot.docs
              .map((doc) => PresenceModel.fromMap(doc.id, doc.data()))
              .toList();
          // Tri local par date décroissante
          presences.sort((a, b) => b.date.compareTo(a.date));
          return presences;
        });
  }}
