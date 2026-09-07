class ParcModel {
  final String id;
  final String nom;
  final String adresse;
  final String wifiNom;
  final double latitude;
  final double longitude;
  final double rayon;
  final String adminId;

  const ParcModel({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.wifiNom,
    required this.latitude,
    required this.longitude,
    required this.rayon,
    required this.adminId,
  });

  factory ParcModel.fromMap(String id, Map<String, dynamic> map) {
    return ParcModel(
      id: id,
      nom: map['nom'] as String? ?? '',
      adresse: map['adresse'] as String? ?? '',
      wifiNom: map['wifiNom'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      rayon: (map['rayon'] as num?)?.toDouble() ?? 10,
      adminId: map['adminId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
      'adresse': adresse,
      'wifiNom': wifiNom,
      'latitude': latitude,
      'longitude': longitude,
      'rayon': rayon,
      'adminId': adminId,
    };
  }
}