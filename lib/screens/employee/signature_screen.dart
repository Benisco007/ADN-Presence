import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
  show FileOptions, Supabase;

import '../../models/user_model.dart';
import 'home_screen.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key, required this.currentUser});

  final UserModel currentUser;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  File? _signatureFile;
  bool _isSaving = false;
  bool _isPicking = false;
  String? _errorMessage;

  Future<void> _chooseSignature() async {
    if (_isPicking || _isSaving) return;
    setState(() => _isPicking = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image == null || !mounted) return;
      setState(() {
        _signatureFile = File(image.path);
        _errorMessage = null;
      });
    } catch (error) {
      if (mounted) setState(() => _errorMessage = 'Impossible d’ouvrir la galerie : $error');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _saveSignature() async {
    final signatureFile = _signatureFile;
    if (signatureFile == null) {
      setState(() => _errorMessage = 'Sélectionnez une image de signature.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    var operation = 'Supabase Storage';
    try {
      final storage = Supabase.instance.client.storage.from('signatures');
      final filePath = '${widget.currentUser.id}.png';
      await storage.upload(
        filePath,
        signatureFile,
        fileOptions: const FileOptions(
          contentType: 'image/png',
          upsert: true,
        ),
      );
      final signatureUrl = storage.getPublicUrl(filePath);

      operation = 'Firestore';
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUser.id)
          .update({'signatureUrl': signatureUrl});

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            currentUser: UserModel(
              id: widget.currentUser.id,
              nom: widget.currentUser.nom,
              prenom: widget.currentUser.prenom,
              poste: widget.currentUser.poste,
              email: widget.currentUser.email,
              role: widget.currentUser.role,
              contact: widget.currentUser.contact,
              signatureUrl: signatureUrl,
              parcId: widget.currentUser.parcId,
            ),
          ),
        ),
      );
    } on FirebaseException catch (error) {
      debugPrint('Erreur Firebase lors de l’enregistrement: ${error.code} ${error.message}');
      if (mounted) {
        setState(() => _errorMessage =
            'Erreur $operation (${error.code}): ${error.message ?? 'opération refusée'}');
      }
    } catch (error) {
      debugPrint('Erreur lors de l’enregistrement: $error');
      if (mounted) {
        setState(() => _errorMessage = 'Erreur $operation: $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signature requise')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Ajoutez votre signature pour continuer.'),
            const SizedBox(height: 24),
            Expanded(
              child: _signatureFile == null
                  ? const Center(child: Icon(Icons.draw, size: 96))
                  : Image.file(_signatureFile!, fit: BoxFit.contain),
            ),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _isSaving || _isPicking ? null : _chooseSignature,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choisir une signature'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isSaving ? null : _saveSignature,
              icon: _isSaving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}