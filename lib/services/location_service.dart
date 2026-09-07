import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/parc_model.dart';

class LocationService {
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<ParcModel?> _getCurrentPark() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final parcId = userDoc.data()?['parcId'] as String?;
    if (parcId == null || parcId.isEmpty) return null;
    final parcDoc = await FirebaseFirestore.instance.collection('parcs').doc(parcId).get();
    if (!parcDoc.exists || parcDoc.data() == null) return null;
    return ParcModel.fromMap(parcDoc.id, parcDoc.data()!);
  }

  // Vérifier via WiFi
  Future<bool> estConnecteAuWifiBureau() async {
    try {
      String? wifiName = await _networkInfo.getWifiName();
      if (wifiName == null) return false;
      // Supprimer les guillemets que Android ajoute parfois
      wifiName = wifiName.replaceAll('"', '');
      final parc = await _getCurrentPark();
      return parc != null && parc.wifiNom.isNotEmpty && wifiName == parc.wifiNom;
    } catch (e) {
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
    } catch (e) {
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