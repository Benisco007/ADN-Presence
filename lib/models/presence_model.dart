class PresenceModel {
  final String id;
  final String userId;
  final DateTime date;
  final DateTime heureArrivee;
  final String type; // 'automatique' ou 'manuel'
  final String statut; // 'present' ou 'absent'

  PresenceModel({
    required this.id,
    required this.userId,
    required this.date,
    required this.heureArrivee,
    required this.type,
    required this.statut,
  });

  factory PresenceModel.fromMap(String id, Map<String, dynamic> map) {
    return PresenceModel(
      id: id,
      userId: map['userId'] ?? '',
      date: (map['date'] as dynamic).toDate(),
      heureArrivee: (map['heureArrivee'] as dynamic).toDate(),
      type: map['type'] ?? 'automatique',
      statut: map['statut'] ?? 'present',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'date': date,
      'heureArrivee': heureArrivee,
      'type': type,
      'statut': statut,
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
    );
  }
}