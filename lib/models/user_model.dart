class UserModel {
  final String id;
  final String nom;
  final String prenom;
  final String poste;
  final String email;
  final String role;
  final String? contact;
  final String? signatureUrl;
  final String? parcId;

  UserModel({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.poste,
    required this.email,
    required this.role,
    this.contact,
    this.signatureUrl,
    this.parcId,
  });

  factory UserModel.fromMap(String id, Map<String, dynamic> map) {
    return UserModel(
      id: id,
      nom: map['nom'] ?? '',
      prenom: map['prenom'] ?? '',
      poste: map['poste'] ?? '',
      email: map['email'] ?? '',
      role: map['role'] ?? 'employe',
      contact: map['contact'],
      signatureUrl: map['signatureUrl'],
      parcId: map['parcId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nom': nom,
      'prenom': prenom,
      'poste': poste,
      'email': email,
      'role': role,
      'contact': contact,
      'signatureUrl': signatureUrl,
      'parcId': parcId,
    };
  }

  bool get signatureComplete => signatureUrl != null && signatureUrl!.isNotEmpty;
}