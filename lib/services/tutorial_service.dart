import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialStep {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;

  TutorialStep({
    required this.title,
    required this.description,
    required this.icon,
    this.iconColor = const Color(0xFF1A73E8),
  });
}

class TutorialService {
  static const String _keySeenAdminTutorial = 'seen_admin_tutorial_v1';
  static const String _keySeenEmployeeTutorial = 'seen_employee_tutorial_v1';

  static Future<bool> hasSeenTutorial({required bool isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(isAdmin ? _keySeenAdminTutorial : _keySeenEmployeeTutorial) ?? false;
  }

  static Future<void> markTutorialSeen({required bool isAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(isAdmin ? _keySeenAdminTutorial : _keySeenEmployeeTutorial, true);
  }

  static List<TutorialStep> getAdminSteps() {
    return [
      TutorialStep(
        title: 'Bienvenue sur ADN Présence\u{00A0}👋',
        description: 'Cette application vous permet de suivre en temps réel la présence et les mouvements des employés sur tous vos parcs.',
        icon: Icons.admin_panel_settings,
        iconColor: const Color(0xFF1A73E8),
      ),
      TutorialStep(
        title: 'Tableau de Bord & Parcs\u{00A0}🏞️',
        description: 'Consultez la liste des parcs et cliquez sur n\'importe quel parc pour voir les employés rattachés, leur heure d\'arrivée et leurs heures supplémentaires.',
        icon: Icons.location_city,
        iconColor: Colors.blue,
      ),
      TutorialStep(
        title: 'Détails des Employés & Pauses\u{00A0}⏱️',
        description: 'Sur la page d\'un parc, vous voyez les heures d\'arrivée, les pauses (sorties/retours) et pouvez corriger l\'heure d\'arrivée d\'un employé si besoin.',
        icon: Icons.timer,
        iconColor: Colors.purple,
      ),
      TutorialStep(
        title: 'Sécurité & Mot de Passe\u{00A0}🔐',
        description: 'Accédez à l\'onglet Sécurité depuis le menu latéral pour changer votre mot de passe à tout moment en toute confidentialité.',
        icon: Icons.security,
        iconColor: Colors.orange,
      ),
      TutorialStep(
        title: 'Rapports & Exporation\u{00A0}📊',
        description: 'Générez des rapports hebdomadaires ou mensuels au format Excel et PDF directement depuis le menu latéral.',
        icon: Icons.analytics,
        iconColor: Colors.green,
      ),
    ];
  }

  static List<TutorialStep> getEmployeeSteps() {
    return [
      TutorialStep(
        title: 'Bienvenue sur ADN Présence\u{00A0}👋',
        description: 'Votre application de pointage simple, rapide et sécurisée.',
        icon: Icons.badge,
        iconColor: const Color(0xFF1A73E8),
      ),
      TutorialStep(
        title: 'Pointage Automatique & GPS/WiFi\u{00A0}📍',
        description: 'Dès que vous êtes connecté au WiFi du bureau ou dans la zone GPS, votre présence est enregistrée automatiquement.',
        icon: Icons.location_on,
        iconColor: Colors.green,
      ),
      TutorialStep(
        title: 'Pointage par QR Code\u{00A0}🟣',
        description: 'Si le mode QR Code est activé par votre administration, scannez simplement le code affiché sur le parc pour valider votre venue.',
        icon: Icons.qr_code_scanner,
        iconColor: Colors.purple,
      ),
      TutorialStep(
        title: 'Historique & Sécurité\u{00A0}🔐',
        description: 'Consultez votre historique de présence quotidien et changez votre mot de passe via l\'icône de sécurité en haut de l\'écran.',
        icon: Icons.history,
        iconColor: Colors.orange,
      ),
    ];
  }

  static void showTutorialDialog(
    BuildContext context, {
    required bool isAdmin,
    VoidCallback? onComplete,
  }) {
    final steps = isAdmin ? getAdminSteps() : getEmployeeSteps();
    int currentStep = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final step = steps[currentStep];
            final isLastStep = currentStep == steps.length - 1;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              contentPadding: const EdgeInsets.all(20),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Indicateur de progression (1/5)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Étape ${currentStep + 1} / ${steps.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                          onPressed: () {
                            markTutorialSeen(isAdmin: isAdmin);
                            Navigator.pop(dialogContext);
                            if (onComplete != null) onComplete();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Icône de l'étape
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: step.iconColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(step.icon, size: 44, color: step.iconColor),
                    ),
                    const SizedBox(height: 16),

                    // Titre
                    Text(
                      step.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      step.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Boutons de navigation
                    Row(
                      children: [
                        if (currentStep > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() => currentStep--);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Précédent',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        if (currentStep > 0) const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (isLastStep) {
                                markTutorialSeen(isAdmin: isAdmin);
                                Navigator.pop(dialogContext);
                                if (onComplete != null) onComplete();
                              } else {
                                setState(() => currentStep++);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: step.iconColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                isLastStep ? 'Terminer\u{00A0}🎉' : 'Suivant',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
