import 'package:cloud_firestore/cloud_firestore.dart';

class Mouvement {
  final DateTime sortie;
  final DateTime? retour;

  Mouvement({required this.sortie, this.retour});

  factory Mouvement.fromMap(Map<String, dynamic> map) {
    return Mouvement(
      sortie: (map['sortie'] as Timestamp).toDate(),
      retour: map['retour'] != null
          ? (map['retour'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sortie': Timestamp.fromDate(sortie),
      'retour': retour != null ? Timestamp.fromDate(retour!) : null,
    };
  }
}

class PresenceModel {
  final String id;
  final String userId;
  final DateTime date;
  final DateTime heureArrivee;
  final String type;
  final String statut;
  final DateTime? heureSortieDefinitive;
  final int heuresSupplementaires; // en minutes
  final List<Mouvement> mouvements;

  PresenceModel({
    required this.id,
    required this.userId,
    required this.date,
    required this.heureArrivee,
    required this.type,
    required this.statut,
    this.heureSortieDefinitive,
    this.heuresSupplementaires = 0,
    this.mouvements = const [],
  });

  factory PresenceModel.fromMap(String id, Map<String, dynamic> map) {
    // Lecture des mouvements (liste vide si absente — compatibilité Phase 1)
    final mouvementsRaw = map['mouvements'] as List<dynamic>? ?? [];
    final mouvements = mouvementsRaw
        .map((m) => Mouvement.fromMap(m as Map<String, dynamic>))
        .toList();

    return PresenceModel(
      id: id,
      userId: map['userId'] ?? '',
      date: (map['date'] as Timestamp).toDate(),
      heureArrivee: (map['heureArrivee'] as Timestamp).toDate(),
      type: map['type'] ?? 'automatique',
      statut: map['statut'] ?? 'present',
      heureSortieDefinitive: map['heureSortieDefinitive'] != null
          ? (map['heureSortieDefinitive'] as Timestamp).toDate()
          : null,
      heuresSupplementaires: map['heuresSupplementaires'] as int? ?? 0,
      mouvements: mouvements,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': Timestamp.fromDate(date),
      'heureArrivee': Timestamp.fromDate(heureArrivee),
      'type': type,
      'statut': statut,
      'heureSortieDefinitive': heureSortieDefinitive != null
          ? Timestamp.fromDate(heureSortieDefinitive!)
          : null,
      'heuresSupplementaires': heuresSupplementaires,
      'mouvements': mouvements.map((m) => m.toMap()).toList(),
    };
  }

  PresenceModel copyWith({DateTime? heureArrivee}) {
    return PresenceModel(
      id: id,
      userId: userId,
      date: date,
      heureArrivee: heureArrivee ?? this.heureArrivee,
      type: type,
      statut: statut,
      heureSortieDefinitive: heureSortieDefinitive,
      heuresSupplementaires: heuresSupplementaires,
      mouvements: mouvements,
    );
  }
}