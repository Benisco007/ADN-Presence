import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/parc_model.dart';
import '../../services/config_service.dart';

class ParksScreen extends StatefulWidget {
  const ParksScreen({super.key});

  @override
  State<ParksScreen> createState() => _ParksScreenState();
}

class _ParksScreenState extends State<ParksScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _configService = ConfigService();

  // Suivi des parcs dont le switch est en cours de mise à jour
  final Set<String> _switchLoading = {};

  Stream<QuerySnapshot<Map<String, dynamic>>> get _parksStream => _firestore
      .collection('parcs')
      .where('adminId', isEqualTo: _auth.currentUser?.uid)
      .snapshots();

  Future<void> _savePark({ParcModel? park}) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: park?.nom);
    final addressController = TextEditingController(text: park?.adresse);
    final wifiController = TextEditingController(text: park?.wifiNom);
    final latitudeController =
        TextEditingController(text: park?.latitude.toString());
    final longitudeController =
        TextEditingController(text: park?.longitude.toString());
    final radiusController =
        TextEditingController(text: park?.rayon.toString() ?? '10');

    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(park == null ? 'Nouveau parc' : 'Modifier le parc'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(nameController, 'Nom du parc', required: true),
                _field(addressController, 'Adresse'),
                _field(wifiController, 'Nom du Wi-Fi'),
                _field(latitudeController, 'Latitude',
                    number: true, required: true),
                _field(longitudeController, 'Longitude',
                    number: true, required: true),
                _field(radiusController, 'Rayon en mètres',
                    number: true, required: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, {
                  'nom': nameController.text.trim(),
                  'adresse': addressController.text.trim(),
                  'wifiNom': wifiController.text.trim(),
                  'latitude': latitudeController.text.trim(),
                  'longitude': longitudeController.text.trim(),
                  'rayon': radiusController.text.trim(),
                });
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    if (values == null || !mounted) return;
    final data = {
      'nom': values['nom'],
      'adresse': values['adresse'],
      'wifiNom': values['wifiNom'],
      'latitude': double.parse(values['latitude']!),
      'longitude': double.parse(values['longitude']!),
      'rayon': double.parse(values['rayon']!),
      'adminId': _auth.currentUser!.uid,
    };
    final collection = _firestore.collection('parcs');
    try {
      if (park == null) {
        await collection.add(data);
      } else {
        await collection.doc(park.id).update(data);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Impossible d\'enregistrer le parc : ${error.code}')),
        );
      }
    }
  }

  TextFormField _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType:
          number ? const TextInputType.numberWithOptions(decimal: true) : null,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) return 'Champ obligatoire';
              if (number && double.tryParse(value.trim()) == null)
                return 'Valeur invalide';
              return null;
            }
          : null,
    );
  }

  Future<void> _deletePark(ParcModel park) async {
    final employees = await _firestore
        .collection('users')
        .where('parcId', isEqualTo: park.id)
        .limit(1)
        .get();
    if (employees.docs.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Retirez d\'abord les employés de ce parc.')),
      );
      return;
    }
    if (!mounted) return;
    final confirmation = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Confirmer la suppression',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer le parc "${park.nom}" ?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler',
                style:
                    TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmation != true) return;
    await _firestore.collection('parcs').doc(park.id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mes parcs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _savePark(),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Nouveau parc'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _parksStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          final parks = snapshot.data?.docs
                  .map((doc) => ParcModel.fromMap(doc.id, doc.data()))
                  .toList() ??
              [];
          if (parks.isEmpty) {
            return const Center(
                child:
                    Text('Aucun parc. Appuyez sur + pour commencer.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: parks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final park = parks[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Infos parc + menu ──
                      Row(
                        children: [
                          const CircleAvatar(
                              child: Icon(Icons.location_city)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  park.nom,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                                Text(
                                  '${park.adresse}\nWi-Fi : ${park.wifiNom}  •  Rayon : ${park.rayon.toStringAsFixed(0)} m',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'edit') _savePark(park: park);
                              if (action == 'delete') _deletePark(park);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'edit', child: Text('Modifier')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Supprimer')),
                            ],
                          ),
                        ],
                      ),

                      const Divider(height: 20),

                      // ── Switch mode de marquage ──
                      StreamBuilder<String>(
                        stream: _configService.ecouterMode(park.id),
                        builder: (context, modeSnapshot) {
                          final mode = modeSnapshot.data ?? 'wifi_gps';
                          final isQrMode = mode == 'qr_code';

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Mode de marquage',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        isQrMode
                                            ? Icons.qr_code_scanner
                                            : Icons.wifi_find,
                                        size: 16,
                                        color: isQrMode
                                            ? Colors.purple
                                            : const Color(0xFF1A73E8),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isQrMode
                                            ? 'QR Code'
                                            : 'WiFi / GPS',
                                        style: TextStyle(
                                          color: isQrMode
                                              ? Colors.purple
                                              : const Color(0xFF1A73E8),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              _switchLoading.contains(park.id)
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.purple,
                                    ),
                                  )
                                : Switch(
                                value: isQrMode,
                                activeColor: Colors.purple,
                                onChanged: (value) async {
                                  setState(() => _switchLoading.add(park.id));
                                  try {
                                    final nouveauMode =
                                        value ? 'qr_code' : 'wifi_gps';
                                    await _configService.changerMode(
                                        park.id, nouveauMode);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(value
                                              ? '🟣 Mode QR Code activé pour ${park.nom}'
                                              : '🔵 Mode WiFi/GPS activé pour ${park.nom}'),
                                          duration:
                                              const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              '❌ Erreur lors du changement de mode : $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _switchLoading.remove(park.id));
                                    }
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}