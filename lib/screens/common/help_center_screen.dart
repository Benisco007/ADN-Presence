import 'package:flutter/material.dart';
import '../../services/tutorial_service.dart';

class FaqItem {
  final String question;
  final String answer;
  final String category; // 'pointage', 'gestion', 'rapports', 'securite'
  final IconData icon;
  final bool forAdmin;
  final bool forEmployee;

  FaqItem({
    required this.question,
    required this.answer,
    required this.category,
    required this.icon,
    this.forAdmin = true,
    this.forEmployee = true,
  });
}

class HelpCenterScreen extends StatefulWidget {
  final bool isAdmin;

  const HelpCenterScreen({super.key, this.isAdmin = true});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'tous';
  String _searchQuery = '';

  final List<FaqItem> _allFaqs = [
    // ── FAQ Spécifiques & communes Pointage ──
    FaqItem(
      question: 'Comment fonctionne le pointage automatique (WiFi & GPS) ?',
      answer:
          'Dès que vous arrivez au bureau, l\'application vérifie si votre téléphone est connecté au réseau WiFi du parc ou s\'il se trouve dans le périmètre GPS défini. Si c\'est le cas, la présence est enregistrée automatiquement.',
      category: 'pointage',
      icon: Icons.wifi,
      forAdmin: true,
      forEmployee: true,
    ),
    FaqItem(
      question: 'Comment marquer ma présence par QR Code ?',
      answer:
          'Si le mode QR Code est activé pour votre parc, appuyez sur le bouton "Scanner le QR Code" depuis l\'accueil, autorisez la caméra et pointez le téléphone vers le code affiché sur la tablette à l\'entrée.',
      category: 'pointage',
      icon: Icons.qr_code_scanner,
      forAdmin: true,
      forEmployee: true,
    ),
    FaqItem(
      question: 'Que faire si ma localisation ou le WiFi ne sont pas détectés ?',
      answer:
          '1. Assurez-vous que le WiFi et le GPS sont activés sur votre téléphone.\n2. Vérifiez que l\'application ADN Présence a l\'autorisation d\'accéder à votre position.\n3. En cas d\'erreur de réseau, vous pouvez utiliser le bouton "Marquage manuel (secours)".',
      category: 'pointage',
      icon: Icons.location_off,
      forAdmin: false,
      forEmployee: true,
    ),
    FaqItem(
      question: 'Comment consulter mon historique personnel de présence ?',
      answer:
          'Depuis votre écran d\'accueil employé, appuyez sur le bouton "Voir mon historique" en bas de page. Vous aurez le détail de vos heures d\'arrivée, vos pauses et vos heures de départ de chaque jour.',
      category: 'pointage',
      icon: Icons.history,
      forAdmin: false,
      forEmployee: true,
    ),

    // ── FAQ Administration des Parcs & Employés (ADMIN SEULEMENT) ──
    FaqItem(
      question: 'Comment consulter le détail et les employés d\'un parc ?',
      answer:
          'Sur le tableau de bord administrateur, cliquez simplement sur n\'importe quelle carte de parc. Une page dédiée s\'ouvrira avec l\'intitulé du parc, la liste détaillée des employés, leurs heures d\'arrivée, sorties et heures supplémentaires.',
      category: 'gestion',
      icon: Icons.location_city,
      forAdmin: true,
      forEmployee: false,
    ),
    FaqItem(
      question: 'Comment corriger l\'heure d\'arrivée d\'un employé ?',
      answer:
          'Ouvrez la page détaillée du parc correspondant, trouvez l\'employé concerné dans la liste et appuyez sur l\'icône du crayon bleu à côté de son heure d\'arrivée. Sélectionnez la nouvelle heure et validez.',
      category: 'gestion',
      icon: Icons.edit_calendar,
      forAdmin: true,
      forEmployee: false,
    ),
    FaqItem(
      question: 'Comment ajouter un nouveau parc ou un nouvel employé ?',
      answer:
          'Ouvrez le menu latéral (Drawer) et sélectionnez "Gestion des Parcs" ou "Gestion des Employés". Cliquez sur le bouton (+) en bas de l\'écran et remplissez le formulaire avec les coordonnées réseau/GPS et identifiants.',
      category: 'gestion',
      icon: Icons.person_add_alt_1,
      forAdmin: true,
      forEmployee: false,
    ),
    FaqItem(
      question: 'Comment basculer un parc en mode QR Code Tablette ?',
      answer:
          'Dans la gestion des parcs ou depuis le Dashboard, sélectionnez le parc souhaité et modifiez son mode de pointage vers "QR Code Tablette". Le changement sera appliqué immédiatement pour tous les employés rattachés.',
      category: 'gestion',
      icon: Icons.qr_code,
      forAdmin: true,
      forEmployee: false,
    ),

    // ── FAQ Rapports & Heures Supplémentaires (ADMIN SEULEMENT) ──
    FaqItem(
      question: 'Comment sont calculées les heures supplémentaires ?',
      answer:
          'Les heures supplémentaires sont calculées automatiquement pour chaque employé en comparant ses heures effectives de présence (arrivée et départ définitif) au temps de travail réglementaire fixé pour son parc.',
      category: 'rapports',
      icon: Icons.more_time,
      forAdmin: true,
      forEmployee: false,
    ),
    FaqItem(
      question: 'Comment générer et exporter les rapports Excel / PDF ?',
      answer:
          'Ouvrez le menu latéral (Drawer) et cliquez sur "Rapports hebdomadaires". Sélectionnez la semaine et le parc souhaités, puis cliquez sur "Exporter Excel" ou "Exporter PDF". Le fichier généré pourra être partagé instantanément.',
      category: 'rapports',
      icon: Icons.analytics,
      forAdmin: true,
      forEmployee: false,
    ),

    // ── FAQ Sécurité & Compte ──
    FaqItem(
      question: 'Comment modifier mon mot de passe ?',
      answer:
          'Allez dans l\'écran Sécurité (icône bouclier pour l\'employé ou via le menu latéral pour l\'admin). Saisissez votre mot de passe actuel puis votre nouveau mot de passe (6 caractères minimum) et validez.',
      category: 'securite',
      icon: Icons.lock_outline,
      forAdmin: true,
      forEmployee: true,
    ),
    FaqItem(
      question: 'Que faire en cas d\'oubli de mot de passe ?',
      answer:
          'Contactez l\'administrateur principal de l\'application afin qu\'il puisse réinitialiser votre accès et vous fournir un mot de passe temporaire.',
      category: 'securite',
      icon: Icons.help_outline,
      forAdmin: false,
      forEmployee: true,
    ),
    FaqItem(
      question: 'Comment réinitialiser le mot de passe d\'un employé ?',
      answer:
          'Accédez à "Gestion des Employés" depuis le menu latéral, sélectionnez l\'employé dans la liste, appuyez sur "Modifier" et définissez son nouveau mot de passe.',
      category: 'securite',
      icon: Icons.admin_panel_settings,
      forAdmin: true,
      forEmployee: false,
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<FaqItem> get _filteredFaqs {
    return _allFaqs.where((faq) {
      // 1. Filtre par rôle (Admin vs Employé)
      final roleMatch = widget.isAdmin ? faq.forAdmin : faq.forEmployee;
      if (!roleMatch) return false;

      // 2. Filtre par catégorie sélectionnée
      if (_selectedCategory != 'tous' && faq.category != _selectedCategory) {
        return false;
      }

      // 3. Filtre par recherche texte
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchQ = faq.question.toLowerCase().contains(q);
        final matchA = faq.answer.toLowerCase().contains(q);
        return matchQ || matchA;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: Text(
          widget.isAdmin ? 'Aide & FAQ Administrateur' : 'Aide & FAQ Employé',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Carte En-tête avec Bouton Tutoriel ──
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(0x191A73E8),
                          child: Icon(
                            Icons.school_outlined,
                            color: Color(0xFF1A73E8),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isAdmin
                                    ? 'Aide Administrateur'
                                    : 'Aide Employé',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.isAdmin
                                    ? 'Guide et réponses aux questions de gestion des parcs et équipes.'
                                    : 'Toutes les réponses pour réussir votre pointage au quotidien.',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          TutorialService.showTutorialDialog(
                            context,
                            isAdmin: widget.isAdmin,
                          );
                        },
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text(
                          widget.isAdmin
                              ? 'Lancer le tutoriel Admin'
                              : 'Lancer le tutoriel Employé',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A73E8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Barre de recherche ──
            TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
              decoration: InputDecoration(
                hintText: widget.isAdmin
                    ? 'Rechercher une question admin (ex: rapport, modif heure)...'
                    : 'Rechercher une question employé (ex: GPS, QR Code, mot de passe)...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1A73E8)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Chips Filtres Catégories selon Rôle ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.isAdmin
                    ? [
                        _chipCategorie('tous', 'Tous'),
                        const SizedBox(width: 8),
                        _chipCategorie('gestion', 'Gestion des Parcs'),
                        const SizedBox(width: 8),
                        _chipCategorie('rapports', 'Rapports & Heures'),
                        const SizedBox(width: 8),
                        _chipCategorie('pointage', 'Modes de Pointage'),
                        const SizedBox(width: 8),
                        _chipCategorie('securite', 'Sécurité'),
                      ]
                    : [
                        _chipCategorie('tous', 'Tous'),
                        const SizedBox(width: 8),
                        _chipCategorie('pointage', 'Pointage & GPS'),
                        const SizedBox(width: 8),
                        _chipCategorie('securite', 'Sécurité & Compte'),
                      ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Liste FAQ ──
            if (_filteredFaqs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Aucune réponse trouvée pour cette recherche.',
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredFaqs.length,
                itemBuilder: (context, index) {
                  final faq = _filteredFaqs[index];
                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ExpansionTile(
                      leading: Icon(faq.icon, color: const Color(0xFF1A73E8)),
                      title: Text(
                        faq.question,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      expandedAlignment: Alignment.topLeft,
                      children: [
                        Text(
                          faq.answer,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipCategorie(String id, String label) {
    final isSelected = _selectedCategory == id;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedCategory = id);
        }
      },
      selectedColor: const Color(0xFF1A73E8),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
