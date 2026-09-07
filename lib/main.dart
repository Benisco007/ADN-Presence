import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'firebase_options.dart';
import 'screens/auth/login_screen.dart';
import 'screens/employee/home_screen.dart';
import 'screens/employee/signature_screen.dart';
import 'screens/admin/dashboard_screen.dart';
import 'models/user_model.dart';
import 'services/export_service.dart';
import 'services/foreground_service.dart';


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

Duration _prochainVendredi() {
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://fwgsgdgmemdhbeooegxr.supabase.co',
  );
  const supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: 'sb_publishable_TQao1KYTy5rDlytKychVaQ_duBZZtgL');
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  if (!kIsWeb) {
    ForegroundPresenceService.initialiser();

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADN Presence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _verifierSession();
  }

  Future<void> _verifierSession() async {
    await Future.delayed(const Duration(milliseconds: 500));

    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Pas de session — aller à la connexion
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    // Session active — récupérer le profil
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      final UserModel userModel =
          UserModel.fromMap(user.uid, doc.data() as Map<String, dynamic>);

    // Debug — à supprimer après test
    print('Role: ${userModel.role}');
    print('SignatureUrl: ${userModel.signatureUrl}');
    print('SignatureComplete: ${userModel.signatureComplete}');

      // Redémarrer le foreground service si employé
      if (!kIsWeb && userModel.role == 'employe') {
        await ForegroundPresenceService.demarrer();
      }

      // Vérifier si signature complète
      if (userModel.role == 'employe' && !userModel.signatureComplete) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SignatureScreen(currentUser: userModel),
          ),
        );
        return;
      }

      // Rediriger selon le rôle
      if (userModel.role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => DashboardScreen(currentUser: userModel)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) => HomeScreen(currentUser: userModel)),
        );
      }
    } catch (e) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1A73E8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_filled, size: 80, color: Colors.white),
            SizedBox(height: 16),
            Text(
              'ADN Presence',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}