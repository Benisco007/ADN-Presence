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

  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      User? user = _auth.currentUser;
      if (user == null || user.email == null) {
        return {'success': false, 'message': 'Utilisateur non connecté.'};
      }

      // 1. Re-authentification avec l'ancien mot de passe
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // 2. Mise à jour du mot de passe dans Firebase Auth
      await user.updatePassword(newPassword);

      return {'success': true, 'message': 'Mot de passe modifié avec succès.'};
    } on FirebaseAuthException catch (e) {
      String message = 'Erreur lors du changement de mot de passe.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'L\'ancien mot de passe est incorrect.';
      } else if (e.code == 'weak-password') {
        message = 'Le nouveau mot de passe est trop faible (minimum 6 caractères).';
      } else if (e.code == 'requires-recent-login') {
        message = 'Veuillez vous re-connecter puis réessayer.';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'Une erreur inattendue est survenue.'};
    }
  }
}