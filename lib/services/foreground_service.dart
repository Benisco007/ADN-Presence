import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'location_service.dart';
import 'presence_service.dart';

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PresenceTaskHandler());
}

class PresenceTaskHandler extends TaskHandler {
  bool _firebaseInitialise = false;
  bool? _dernierEtatAuBureau;

  // Clés SharedPreferences
  static const String _cleEtatAuBureau = 'etat_au_bureau';
  static const String _cleMouvementsEnAttente = 'mouvements_en_attente';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    if (!_firebaseInitialise) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseInitialise = true;
    }
    // Restaurer le dernier état connu
    final prefs = await SharedPreferences.getInstance();
    _dernierEtatAuBureau = prefs.getBool(_cleEtatAuBureau);
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final prefs = await SharedPreferences.getInstance();

      // ── Vérifier le mode du parc (sans Firebase si pas de connexion) ──
      bool modeQr = false;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final parcId = userDoc.data()?['parcId'] as String?;

        if (parcId != null && parcId.isNotEmpty) {
          final configDoc = await FirebaseFirestore.instance
              .collection('config')
              .doc(parcId)
              .get();
          modeQr =
              (configDoc.data()?['modeMarquage'] as String? ?? 'wifi_gps') ==
                  'qr_code';
          // Sauvegarder le mode localement
          await prefs.setBool('mode_qr', modeQr);
        }
      } catch (_) {
        // Pas de connexion → utiliser le mode sauvegardé localement
        modeQr = prefs.getBool('mode_qr') ?? false;
      }

      if (modeQr) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'PresenceApp',
          notificationText:
              '📱 Mode QR Code — scannez la tablette à l\'entrée',
        );
        return;
      }

      // ── Détecter la position (fonctionne SANS internet) ──
      final locationService = LocationService();
      final bool auBureau = await locationService.estAuBureau();
      final DateTime maintenant = DateTime.now();

      // Sauvegarder l'état actuel localement
      await prefs.setBool(_cleEtatAuBureau, auBureau);

      // ── Tenter de synchroniser les mouvements en attente ──
      await _synchroniserMouvementsEnAttente(prefs, user.uid);

      // ── Vérifier si déjà marqué ──
      bool dejaMarque = false;
      try {
        final presenceService = PresenceService();
        dejaMarque = await presenceService.dejaMarqueAujourdhui();
        await prefs.setBool('deja_marque', dejaMarque);
      } catch (_) {
        dejaMarque = prefs.getBool('deja_marque') ?? false;
      }

      if (!dejaMarque) {
        // ── Pas encore marqué ──
        if (auBureau) {
          try {
            final presenceService = PresenceService();
            final bool succes =
                await presenceService.marquerPresence('automatique');
            if (succes) {
              _dernierEtatAuBureau = true;
              await prefs.setBool(_cleEtatAuBureau, true);
              await prefs.setBool('deja_marque', true);
              FlutterForegroundTask.updateService(
                notificationTitle: 'PresenceApp',
                notificationText:
                    '✅ Présence marquée à ${maintenant.hour}h${maintenant.minute.toString().padLeft(2, '0')}',
              );
            }
          } catch (_) {
            FlutterForegroundTask.updateService(
              notificationTitle: 'PresenceApp',
              notificationText: '⚠️ Dans la zone — en attente de connexion',
            );
          }
        } else {
          final bool apres8h15 = maintenant.hour > 8 ||
              (maintenant.hour == 8 && maintenant.minute >= 15);
          if (apres8h15) {
            FlutterForegroundTask.updateService(
              notificationTitle: '⚠️ Présence non marquée',
              notificationText: 'Vous n\'êtes pas détecté dans votre zone.',
            );
          }
        }
        _dernierEtatAuBureau = auBureau;
        return;
      }

      // ── Présence marquée → détecter les changements ──
      if (_dernierEtatAuBureau == null) {
        _dernierEtatAuBureau = auBureau;
        FlutterForegroundTask.updateService(
          notificationTitle: 'PresenceApp',
          notificationText: auBureau
              ? '✅ Présence enregistrée aujourd\'hui'
              : '📍 Hors zone — surveillance active',
        );
        return;
      }

      // ── Était au bureau → maintenant dehors ──
      if (_dernierEtatAuBureau == true && !auBureau) {
        _dernierEtatAuBureau = false;

        final mouvement = {
          'type': 'sortie',
          'heure': maintenant.toIso8601String(),
        };

        // Tenter d'écrire dans Firebase
        bool ecritDansFirebase = false;
        try {
          final presenceService = PresenceService();
          await presenceService.enregistrerSortie();
          ecritDansFirebase = true;
        } catch (_) {
          // Pas de connexion → sauvegarder localement
        }

        if (!ecritDansFirebase) {
          await _ajouterMouvementEnAttente(prefs, mouvement);
        }

        final bool apres18h = maintenant.hour >= 18;
        FlutterForegroundTask.updateService(
          notificationTitle: 'PresenceApp',
          notificationText: apres18h
              ? '🏠 Bonne soirée — présence terminée'
              : '📍 Sortie détectée à ${maintenant.hour}h${maintenant.minute.toString().padLeft(2, '0')}',
        );
        return;
      }

      // ── Était dehors → maintenant au bureau ──
      if (_dernierEtatAuBureau == false && auBureau) {
        _dernierEtatAuBureau = true;

        final mouvement = {
          'type': 'retour',
          'heure': maintenant.toIso8601String(),
        };

        // Tenter d'écrire dans Firebase
        bool ecritDansFirebase = false;
        try {
          final presenceService = PresenceService();
          await presenceService.enregistrerRetour();
          ecritDansFirebase = true;
        } catch (_) {
          // Pas de connexion → sauvegarder localement
        }

        if (!ecritDansFirebase) {
          await _ajouterMouvementEnAttente(prefs, mouvement);
        }

        FlutterForegroundTask.updateService(
          notificationTitle: 'PresenceApp',
          notificationText:
              '✅ Retour détecté à ${maintenant.hour}h${maintenant.minute.toString().padLeft(2, '0')}',
        );
        return;
      }

      // ── Pas de changement ──
      FlutterForegroundTask.updateService(
        notificationTitle: 'PresenceApp',
        notificationText: auBureau
            ? '✅ Présence enregistrée aujourd\'hui'
            : '📍 Hors zone — surveillance active',
      );
    } catch (e) {
      // Silencieux
    }
  }

  // Ajouter un mouvement dans la file d'attente locale
  Future<void> _ajouterMouvementEnAttente(
    SharedPreferences prefs,
    Map<String, dynamic> mouvement,
  ) async {
    final String raw = prefs.getString(_cleMouvementsEnAttente) ?? '[]';
    final List<dynamic> liste = jsonDecode(raw);
    liste.add(mouvement);
    await prefs.setString(_cleMouvementsEnAttente, jsonEncode(liste));
  }

  // Synchroniser les mouvements en attente avec Firebase
  Future<void> _synchroniserMouvementsEnAttente(
    SharedPreferences prefs,
    String uid,
  ) async {
    final String raw = prefs.getString(_cleMouvementsEnAttente) ?? '[]';
    final List<dynamic> liste = jsonDecode(raw);
    if (liste.isEmpty) return;

    try {
      final presenceService = PresenceService();

      for (final item in liste) {
        final type = item['type'] as String;
        if (type == 'sortie') {
          await presenceService.enregistrerSortie();
        } else if (type == 'retour') {
          await presenceService.enregistrerRetour();
        }
      }

      // Vider la file d'attente après synchronisation réussie
      await prefs.setString(_cleMouvementsEnAttente, '[]');

      FlutterForegroundTask.updateService(
        notificationTitle: 'PresenceApp',
        notificationText: '🔄 Mouvements synchronisés',
      );
    } catch (_) {
      // Pas encore de connexion → on réessaiera au prochain cycle
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

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
        eventAction: ForegroundTaskEventAction.repeat(2 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> demarrer() async {
    await FlutterForegroundTask.requestNotificationPermission();
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