import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/presence_model.dart';

class PresenceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ── Helpers date ──
  DateTime get _debutJour {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _finJour => _debutJour.add(const Duration(days: 1));

  // Récupérer le document de présence du jour (null si absent)
  Future<DocumentSnapshot<Map<String, dynamic>>?> _presenceDuJour() async {
    final uid = _auth.currentUser!.uid;
    final snapshot = await _firestore
        .collection('presences')
        .where('userId', isEqualTo: uid)
        .get();

    final docs = snapshot.docs.where((doc) {
      final dateField = doc.data()['date'];
      if (dateField == null) return false;
      final datePresence = (dateField as Timestamp).toDate();
      return datePresence.isAfter(_debutJour) &&
              datePresence.isBefore(_finJour) ||
          datePresence.isAtSameMomentAs(_debutJour);
    }).toList();

    return docs.isEmpty ? null : docs.first;
  }

  // Vérifier si déjà marqué aujourd'hui
  Future<bool> dejaMarqueAujourdhui() async {
    final doc = await _presenceDuJour();
    return doc != null;
  }

  // Marquer la présence
  Future<bool> marquerPresence(String type) async {
    try {
      bool dejaMarque = await dejaMarqueAujourdhui();
      if (dejaMarque) return false;

      final uid = _auth.currentUser!.uid;
      final maintenant = DateTime.now();

      await _firestore.collection('presences').add({
        'userId': uid,
        'date': Timestamp.fromDate(maintenant),
        'heureArrivee': Timestamp.fromDate(maintenant),
        'type': type,
        'statut': 'present',
        'mouvements': [],
        'heuresSupplementaires': 0,
        'heureSortieDefinitive': null,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  // ── SUIVI DES MOUVEMENTS ──

  // Enregistrer une sortie de zone
  Future<void> enregistrerSortie() async {
    try {
      final doc = await _presenceDuJour();
      if (doc == null) return; // Pas de présence marquée aujourd'hui

      final data = doc.data()!;
      final mouvementsRaw = data['mouvements'] as List<dynamic>? ?? [];

      // Vérifier qu'il n'y a pas déjà une sortie sans retour
      final dejaSorti = mouvementsRaw.any((m) {
        final map = m as Map<String, dynamic>;
        return map['retour'] == null;
      });
      if (dejaSorti) return; // Sortie déjà enregistrée, pas de doublon

      final maintenant = DateTime.now();
      final nouveauMouvement = {
        'sortie': Timestamp.fromDate(maintenant),
        'retour': null,
      };

      await _firestore.collection('presences').doc(doc.id).update({
        'mouvements': FieldValue.arrayUnion([nouveauMouvement]),
      });
    } catch (e) {
      // Silencieux
    }
  }

  // Enregistrer un retour dans la zone
  Future<void> enregistrerRetour() async {
    try {
      final doc = await _presenceDuJour();
      if (doc == null) return;

      final data = doc.data()!;
      final mouvementsRaw =
          List<Map<String, dynamic>>.from(data['mouvements'] ?? []);

      // Trouver le dernier mouvement sans retour
      int indexSansRetour = -1;
      for (int i = mouvementsRaw.length - 1; i >= 0; i--) {
        if (mouvementsRaw[i]['retour'] == null) {
          indexSansRetour = i;
          break;
        }
      }
      if (indexSansRetour == -1) return; // Pas de sortie en cours

      final maintenant = DateTime.now();
      mouvementsRaw[indexSansRetour]['retour'] =
          Timestamp.fromDate(maintenant);

      // Calculer les heures sup si après 18h
      await _calculerHeuresSup(doc.id, mouvementsRaw, maintenant);

      await _firestore.collection('presences').doc(doc.id).update({
        'mouvements': mouvementsRaw,
      });
    } catch (e) {
      // Silencieux
    }
  }

  // Enregistrer la sortie définitive (fin de journée)
  Future<void> enregistrerSortieDefinitive() async {
    try {
      final doc = await _presenceDuJour();
      if (doc == null) return;

      final maintenant = DateTime.now();
      final heureFinJournee = DateTime(
        maintenant.year,
        maintenant.month,
        maintenant.day,
        18, // 18h = fin de journée
      );

      int minutesSup = 0;
      if (maintenant.isAfter(heureFinJournee)) {
        minutesSup = maintenant.difference(heureFinJournee).inMinutes;
      }

      await _firestore.collection('presences').doc(doc.id).update({
        'heureSortieDefinitive': Timestamp.fromDate(maintenant),
        'heuresSupplementaires': minutesSup,
      });
    } catch (e) {
      // Silencieux
    }
  }

  // Calcul interne des heures supplémentaires
  Future<void> _calculerHeuresSup(
    String presenceId,
    List<Map<String, dynamic>> mouvements,
    DateTime maintenant,
  ) async {
    final heureFinJournee = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
      18,
    );
    if (!maintenant.isAfter(heureFinJournee)) return;

    final minutesSup = maintenant.difference(heureFinJournee).inMinutes;
    await _firestore.collection('presences').doc(presenceId).update({
      'heuresSupplementaires': minutesSup,
    });
  }

  // Récupérer les présences de l'utilisateur connecté
  Stream<List<PresenceModel>> mesPresences() {
    final uid = _auth.currentUser!.uid;
    return _firestore
        .collection('presences')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final presences = snapshot.docs
          .map((doc) => PresenceModel.fromMap(doc.id, doc.data()))
          .toList();
      presences.sort((a, b) => b.date.compareTo(a.date));
      return presences;
    });
  }

  // Récupérer toutes les présences (pour l'admin)
  Stream<List<PresenceModel>> toutesLesPresences() {
    return _firestore.collection('presences').snapshots().map((snapshot) {
      final presences = snapshot.docs
          .map((doc) => PresenceModel.fromMap(doc.id, doc.data()))
          .toList();
      presences.sort((a, b) => b.date.compareTo(a.date));
      return presences;
    });
  }
}