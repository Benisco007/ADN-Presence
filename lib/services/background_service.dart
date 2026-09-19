import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'export_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (task == 'envoi_rapport_vendredi') {
        await ExportService().envoyerMailHebdomadaire();
      }
    } catch (e) {
      return Future.value(false);
    }
    return Future.value(true);
  });
}

class BackgroundService {
  static const String taskName = 'verifier_presence_auto';

  static Duration _prochainVendredi() {
    DateTime maintenant = DateTime.now();
    int joursRestants = DateTime.friday - maintenant.weekday;
    if (joursRestants <= 0) joursRestants += 7;
    DateTime vendredi = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day + joursRestants,
      18,
      0,
    );
    return vendredi.difference(maintenant);
  }

  // Initialiser la tâche périodique
  static Future<void> initialiser() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      'envoi_rapport_vendredi',
      'envoi_rapport_vendredi',
      frequency: const Duration(days: 7),
      initialDelay: _prochainVendredi(),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  // Annuler la tâche
  static Future<void> annuler() async {
    await Workmanager().cancelByUniqueName(taskName);
    await Workmanager().cancelByUniqueName('envoi_rapport_vendredi');
  }
}