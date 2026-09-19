import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'presence_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PresenceTaskHandler());
}

// ─────────────────────────────────────────────────────────────────────────────
// PresenceTaskHandler — Gestionnaire du service de présence en arrière-plan
//
// NOUVELLE STRATÉGIE (A + B) :
// • La détection (Sortie/Retour) et la notification sont 100% gérées par Kotlin natif
//   (WifiZoneReceiver.kt) pour survivre au Task Killer de TECNO/Xiaomi.
// • Ce fichier Dart (onRepeatEvent) ne sert plus qu'à :
//   1. Mettre à jour le SSID du bureau en cache depuis Firestore.
//   2. Vider la file locale 'flutter.mouvements_en_attente' vers Firestore
//      (synchronisation silencieuse en arrière-plan).
// ─────────────────────────────────────────────────────────────────────────────
class PresenceTaskHandler extends TaskHandler {
  bool _firebaseInitialise = false;

  static const String _cleMouvements = 'mouvements_en_attente';
  static const String _cleModeQr = 'mode_qr';
  static const String _cleSsidBureau = 'ssid_bureau_cache';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _initFirebase();
    // Exécuter une première synchronisation immédiatement
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await _mettreAJourConfigBureau(prefs, user.uid);
        await _synchroniserMouvementsEnAttente(prefs, user.uid);
      }
    } catch (_) {}
  }

  Future<void> _initFirebase() async {
    if (_firebaseInitialise) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseInitialise = true;
    } catch (_) {
      _firebaseInitialise = true;
    }
  }

  @override
  void onReceiveData(Object data) {
    // Ignoré : géré par Kotlin natif
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    try {
      await _initFirebase();

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();

      // 1. Mettre à jour la config (SSID) pour le Kotlin
      await _mettreAJourConfigBureau(prefs, user.uid);

      // 2. Vider la file d'attente vers Firestore (Synchronisation)
      await _synchroniserMouvementsEnAttente(prefs, user.uid);

    } catch (_) {}
  }

  Future<void> _mettreAJourConfigBureau(SharedPreferences prefs, String uid) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 4));
      final parcId = userDoc.data()?['parcId'] as String?;

      if (parcId != null && parcId.isNotEmpty) {
        final parcDoc = await FirebaseFirestore.instance
            .collection('parcs')
            .doc(parcId)
            .get()
            .timeout(const Duration(seconds: 4));

        final data = parcDoc.data();
        if (data != null) {
          final modeQr = (data['modeMarquage'] as String? ?? 'wifi_gps') == 'qr_code';
          await prefs.setBool(_cleModeQr, modeQr);

          final String ssidBureau = data['wifiNom'] as String? ?? '';
          if (ssidBureau.isNotEmpty) {
            await prefs.setString(_cleSsidBureau, ssidBureau);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _synchroniserMouvementsEnAttente(SharedPreferences prefs, String uid) async {
    final String raw = prefs.getString(_cleMouvements) ?? '[]';
    final List<dynamic> liste = jsonDecode(raw);
    if (liste.isEmpty) return;

    try {
      final presenceService = PresenceService();
      
      // Essayer de synchroniser chaque mouvement
      for (final item in liste) {
        final type = item['type'] as String;
        final heureRaw = item['heure'] as String?;
        final heureReelle = heureRaw != null ? DateTime.tryParse(heureRaw) : null;
        
        if (type == 'sortie') {
          await presenceService.enregistrerSortie(heureReelle: heureReelle);
        } else if (type == 'retour') {
          await presenceService.enregistrerRetour(heureReelle: heureReelle);
        }
      }
      
      // Si on arrive ici sans erreur, tous les mouvements sont synchronisés
      await prefs.setString(_cleMouvements, '[]');
      print("Synchronisation réussie: \${liste.length} mouvements");
    } catch (_) {
      // Échec de la synchronisation (pas de réseau, etc.), on garde la file
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
  @override
  void onNotificationButtonPressed(String id) {}
  @override
  void onNotificationPressed() {}
}

class ForegroundPresenceService {
  static void initialiser() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'presence_channel',
        channelName: 'PresenceApp',
        channelDescription: 'Surveillance de présence active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Intervalle de 3 minutes pour synchroniser les logs Firebase
        eventAction: ForegroundTaskEventAction.repeat(3 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> demarrer() async {
    await FlutterForegroundTask.requestNotificationPermission();
    
    // ÉTAPE A : Demander d'ignorer les optimisations de batterie (vital pour TECNO/Xiaomi)
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      notificationTitle: 'PresenceApp',
      notificationText: '🟢 Surveillance de présence active...',
      callback: startCallback,
    );
  }

  static Future<void> arreter() async {
    await FlutterForegroundTask.stopService();
  }
}