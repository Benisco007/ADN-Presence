import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/parc_model.dart';

class LocationService {
  final NetworkInfo _networkInfo = NetworkInfo();

  static const String _cleParc = 'parc_cache';

  // Récupérer le parc — Firebase d'abord, cache local si pas de connexion
  Future<ParcModel?> _getCurrentPark() async {
    try {
      // Tenter Firebase
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return _parcDepuisCache();

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));

      final parcId = userDoc.data()?['parcId'] as String?;
      if (parcId == null || parcId.isEmpty) return _parcDepuisCache();

      final parcDoc = await FirebaseFirestore.instance
          .collection('parcs')
          .doc(parcId)
          .get()
          .timeout(const Duration(seconds: 5));

      if (!parcDoc.exists || parcDoc.data() == null) return _parcDepuisCache();

      final parc = ParcModel.fromMap(parcDoc.id, parcDoc.data()!);

      // Sauvegarder dans le cache local
      await _sauvegarderParcEnCache(parc);

      return parc;
    } catch (_) {
      // Pas de connexion → utiliser le cache
      return _parcDepuisCache();
    }
  }

  // Lire le parc depuis SharedPreferences
  Future<ParcModel?> _parcDepuisCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_cleParc);
      if (raw == null) return null;
      final Map<String, dynamic> map = jsonDecode(raw);
      return ParcModel.fromMap(map['id'] as String, map);
    } catch (_) {
      return null;
    }
  }

  // Sauvegarder le parc dans SharedPreferences
  Future<void> _sauvegarderParcEnCache(ParcModel parc) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = {
        'id': parc.id,
        'nom': parc.nom,
        'adresse': parc.adresse,
        'wifiNom': parc.wifiNom,
        'latitude': parc.latitude,
        'longitude': parc.longitude,
        'rayon': parc.rayon,
        'adminId': parc.adminId,
      };
      await prefs.setString(_cleParc, jsonEncode(map));
    } catch (_) {}
  }

  // Vérifier via WiFi
  Future<bool> estConnecteAuWifiBureau() async {
    try {
      String? wifiName = await _networkInfo.getWifiName();
      if (wifiName == null) return false;
      wifiName = wifiName.replaceAll('"', '');
      final parc = await _getCurrentPark();
      return parc != null &&
          parc.wifiNom.isNotEmpty &&
          wifiName == parc.wifiNom;
    } catch (_) {
      return false;
    }
  }

  // Vérifier via GPS
  Future<bool> estDansLaZone() async {
    try {
      bool serviceActif = await Geolocator.isLocationServiceEnabled();
      if (!serviceActif) return false;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return false;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final parc = await _getCurrentPark();
      if (parc == null) return false;

      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        parc.latitude,
        parc.longitude,
      );

      return distance <= parc.rayon;
    } catch (_) {
      return false;
    }
  }

  // Vérification combinée WiFi + GPS
  Future<bool> estAuBureau() async {
    bool wifi = await estConnecteAuWifiBureau();
    if (wifi) return true;
    bool gps = await estDansLaZone();
    return gps;
  }
}