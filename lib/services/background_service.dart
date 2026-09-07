import 'package:workmanager/workmanager.dart';

class BackgroundService {
  static const String taskName = 'verifier_presence_auto';

  // Initialiser la tâche périodique
  static Future<void> initialiser() async {
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  // Annuler la tâche
  static Future<void> annuler() async {
    await Workmanager().cancelByUniqueName(taskName);
  }
}