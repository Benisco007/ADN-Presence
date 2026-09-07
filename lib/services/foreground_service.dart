import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../firebase_options.dart';
import 'location_service.dart';
import 'presence_service.dart';

// Handler qui tourne en arrière-plan
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(PresenceTaskHandler());
}

class PresenceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final presenceService = PresenceService();
      bool dejaMarque = await presenceService.dejaMarqueAujourdhui();

      // Si déjà marqué — mettre à jour la notification et stop
      if (dejaMarque) {
        FlutterForegroundTask.updateService(
          notificationTitle: 'PresenceApp',
          notificationText: '✅ Présence enregistrée aujourd\'hui',
        );
        return;
      }

      // ✅ PRIORITÉ 1 : Vérifier la position (WiFi + GPS) peu importe l'heure
      final locationService = LocationService();
      bool auBureau = await locationService.estAuBureau();

      if (auBureau) {
        // L'employé est dans la zone → marquage automatique immédiat
        final DateTime maintenant = DateTime.now();
        bool succes = await presenceService.marquerPresence('automatique');
        if (succes) {
          FlutterForegroundTask.updateService(
            notificationTitle: 'PresenceApp',
            notificationText:
                '✅ Présence marquée automatiquement à ${maintenant.hour}h${maintenant.minute.toString().padLeft(2, '0')}',
          );
        }
        return;
      }

      // ✅ PRIORITÉ 2 : Pas dans la zone + après 8h15 → rappel de marquage manuel
      final DateTime maintenant = DateTime.now();
      final bool apres8h15 = maintenant.hour > 8 ||
          (maintenant.hour == 8 && maintenant.minute >= 15);

      if (apres8h15) {
        FlutterForegroundTask.updateService(
          notificationTitle: '⚠️ Présence non marquée',
          notificationText:
              'Vous n\'êtes pas détecté dans votre zone. Marquez manuellement si nécessaire.',
        );
      }
      // Avant 8h15 et hors zone → rien (l'employé est peut-être en route)

    } catch (e) {
      // Continuer silencieusement
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
  // Initialiser le service
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
        eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
      ),
    );
  }

  // Démarrer le service
  static Future<void> demarrer() async {
    // Demander les permissions nécessaires
    await FlutterForegroundTask.requestNotificationPermission();

    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: 'PresenceApp',
      notificationText: '🟢 Surveillance de présence active...',
      callback: startCallback,
    );
  }

  // Arrêter le service (à la déconnexion)
  static Future<void> arreter() async {
    await FlutterForegroundTask.stopService();
  }
}