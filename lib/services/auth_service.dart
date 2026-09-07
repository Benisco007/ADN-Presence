import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'foreground_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<UserModel?> login(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(result.user!.uid)
          .get();

      UserModel user = UserModel.fromMap(
          result.user!.uid, doc.data() as Map<String, dynamic>);

      // Démarrer le foreground service si c'est un employé
      if (user.role == 'employe') {
        await ForegroundPresenceService.demarrer();
      }

      return user;
    } catch (e) {
      return null;
    }
  }

  Future<void> logout() async {
    // Arrêter le service à la déconnexion
    await ForegroundPresenceService.arreter();
    await _auth.signOut();
  }

  Future<UserModel?> getCurrentUserProfile() async {
    try {
      User? user = _auth.currentUser;
      if (user == null) return null;

      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      return UserModel.fromMap(user.uid, doc.data() as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }
}