import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, Supabase;
import '../../models/user_model.dart';
import '../../models/parc_model.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();

  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _posteController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _contactController = TextEditingController();

  File? _signatureFile;
  String? _selectedParcId;
  bool _isLoading = false;

  Future<void> _choisirSignature() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      setState(() => _signatureFile = File(image.path));
    }
  }

  Future<String?> _uploaderSignature(String uid) async {
    if (_signatureFile == null) return null;
    final storage = Supabase.instance.client.storage.from('signatures');
    final filePath = '$uid.png';
    await storage.upload(
      filePath,
      _signatureFile!,
      fileOptions: const FileOptions(
        contentType: 'image/png',
        upsert: true,
      ),
    );
    return storage.getPublicUrl(filePath);
  }

  Future<void> _ajouterEmploye() async {
    if (_nomController.text.isEmpty ||
        _prenomController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _contactController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs obligatoires.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Créer le compte Firebase Auth
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final String uid = result.user!.uid;

      // Uploader la signature si fournie
      String? signatureUrl = await _uploaderSignature(uid);

      // Enregistrer dans Firestore
      await _firestore.collection('users').doc(uid).set({
        'nom': _nomController.text.trim(),
        'prenom': _prenomController.text.trim(),
        'poste': _posteController.text.trim(),
        'email': _emailController.text.trim(),
        'contact': _contactController.text.trim(),
        'role': 'employe',
        'parcId': _selectedParcId,
        'signatureUrl': signatureUrl,
      });

      // Notification si signature manquante
      if (signatureUrl == null) {
        await _firestore.collection('notifications').add({
          'message':
              'La signature de ${_prenomController.text.trim()} ${_nomController.text.trim()} '
              'n\'a pas encore été fournie.',
          'date': DateTime.now(),
          'lu': false,
          'adminId': _auth.currentUser!.uid,
        });
      }

      _viderFormulaire();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(signatureUrl != null
              ? '✅ Employé ajouté avec succès !'
              : '✅ Employé ajouté — signature manquante, l\'employé devra signer à sa première connexion.'),
          backgroundColor: signatureUrl != null ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : ${e.toString()}')),
      );
    }

    setState(() => _isLoading = false);
  }

  void _viderFormulaire() {
    _nomController.clear();
    _prenomController.clear();
    _posteController.clear();
    _emailController.clear();
    _passwordController.clear();
    _contactController.clear();
    _selectedParcId = null;
    setState(() => _signatureFile = null);
  }

  void _afficherFormulaireAjout() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ajouter un employé',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _champ(_prenomController, 'Prénom *', Icons.person),
                const SizedBox(height: 10),
                _champ(_nomController, 'Nom *', Icons.person_outline),
                const SizedBox(height: 10),
                _champ(_posteController, 'Poste *', Icons.work),
                const SizedBox(height: 10),
                _champ(_contactController, 'Contact *', Icons.phone,
                    isPhone: true),
                const SizedBox(height: 10),
                _champ(_emailController, 'Email *', Icons.email,
                    isEmail: true),
                const SizedBox(height: 10),
                _champ(_passwordController, 'Mot de passe *', Icons.lock,
                    isPassword: true),
                const SizedBox(height: 16),

                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _firestore
                      .collection('parcs')
                      .where('adminId', isEqualTo: _auth.currentUser?.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final parcs = snapshot.data?.docs
                            .map((doc) => ParcModel.fromMap(doc.id, doc.data()))
                            .toList() ??
                        [];
                    return DropdownButtonFormField<String>(
                      value: _selectedParcId,
                      decoration: const InputDecoration(
                        labelText: 'Parc *',
                        prefixIcon: Icon(Icons.location_city),
                        border: OutlineInputBorder(),
                      ),
                      items: parcs
                          .map((parc) => DropdownMenuItem(
                                value: parc.id,
                                child: Text(parc.nom),
                              ))
                          .toList(),
                      onChanged: (value) {
                        _selectedParcId = value;
                        setModalState(() {});
                      },
                      validator: (value) =>
                          value == null ? 'Sélectionnez un parc' : null,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Upload signature (facultatif)
                const Text(
                  'Signature (facultatif)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    await _choisirSignature();
                    setModalState(() {});
                  },
                  child: Container(
                    width: double.infinity,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _signatureFile != null
                            ? Colors.green
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    child: _signatureFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _signatureFile!,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.upload_file,
                                  color: Colors.grey.shade400, size: 32),
                              const SizedBox(height: 6),
                              Text(
                                'Appuyez pour uploader la signature',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_signatureFile != null)
                  TextButton.icon(
                    onPressed: () => setModalState(() => _signatureFile = null),
                    icon: const Icon(Icons.clear, color: Colors.red, size: 16),
                    label: const Text('Supprimer',
                        style: TextStyle(color: Colors.red)),
                  ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _ajouterEmploye,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Ajouter l\'employé',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _champ(
    TextEditingController controller,
    String label,
    IconData icone, {
    bool isEmail = false,
    bool isPassword = false,
    bool isPhone = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail
          ? TextInputType.emailAddress
          : isPhone
              ? TextInputType.phone
              : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icone),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _supprimerEmploye(UserModel employe) async {
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Confirmer la suppression', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer l\'employé ${employe.prenom} ${employe.nom} ?\n\nCette action est irréversible.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmation != true) return;

    try {
      await _firestore.collection('users').doc(employe.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('L\'employé ${employe.prenom} ${employe.nom} a été supprimé.')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de la suppression: $err')),
      );
    }
  }

  Future<void> _affecterParc(UserModel employe) async {
    final snapshot = await _firestore
      .collection('parcs')
      .where('adminId', isEqualTo: _auth.currentUser?.uid)
      .get();
    if (!mounted) return;

    final parcs = snapshot.docs
        .map((doc) => ParcModel.fromMap(doc.id, doc.data()))
        .toList();
    if (parcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Créez d’abord un parc.')),
      );
      return;
    }

    final parcId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Parc de ${employe.prenom} ${employe.nom}'),
        content: DropdownButtonFormField<String>(
          initialValue: parcs.any((parc) => parc.id == employe.parcId)
              ? employe.parcId
              : null,
          decoration: const InputDecoration(
            labelText: 'Sélectionner un parc',
            border: OutlineInputBorder(),
          ),
          items: parcs
              .map((parc) => DropdownMenuItem(
                    value: parc.id,
                    child: Text(parc.nom),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) Navigator.pop(dialogContext, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );

    if (parcId == null || !mounted) return;
    try {
      await _firestore.collection('users').doc(employe.id).update({
        'parcId': parcId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Employé affecté au parc.')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible d’affecter le parc : ${error.code}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A73E8),
        title: const Text('Gestion des employés',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _afficherFormulaireAjout,
        backgroundColor: const Color(0xFF1A73E8),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('users')
            .where('role', isEqualTo: 'employe')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('Aucun employé. Appuyez sur + pour en ajouter.'),
            );
          }

          List<UserModel> employes = snapshot.data!.docs
              .map((doc) => UserModel.fromMap(
                  doc.id, doc.data() as Map<String, dynamic>))
              .toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: employes.length,
            itemBuilder: (context, index) {
              UserModel e = employes[index];
              bool signatureOk = e.signatureComplete;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: signatureOk
                        ? Colors.transparent
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          const Color(0xFF1A73E8).withOpacity(0.1),
                      child: Text(
                        e.prenom.isEmpty ? '?' : e.prenom[0].toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF1A73E8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${e.prenom} ${e.nom}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          Text(e.poste,
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12)),
                          Text(e.contact ?? '',
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 11)),
                          if (!signatureOk)
                            const Text(
                              '⚠️ Signature manquante',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.location_city,
                        color: e.parcId == null ? Colors.orange : Colors.blue,
                      ),
                      tooltip: e.parcId == null
                          ? 'Affecter à un parc'
                          : 'Modifier le parc',
                      onPressed: () => _affecterParc(e),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Supprimer l\'employé',
                      onPressed: () => _supprimerEmploye(e),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}