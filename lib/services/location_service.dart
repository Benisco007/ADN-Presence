import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/parc_model.dart';

/// Résultat détaillé du contrôle de zone GPS — permet d'afficher un
/// message précis à l'utilisateur en cas d'échec.
class ZoneCheckResult {
  final bool dansLaZone;
  final String message; // Message destiné à l'utilisateur
  final double? distanceM; // Distance calculée (null si position non obtenue)
  final double? rayonM; // Rayon configuré du parc

  const ZoneCheckResult({
    required this.dansLaZone,
    required this.message,
    this.distanceM,
    this.rayonM,
  });
}

class LocationService {
  final NetworkInfo _networkInfo = NetworkInfo();

  static const String _cleParc = 'parc_cache';

  // ── Clés écrites par WifiZoneReceiver.kt (préfixe Flutter) ──
  static const String _cleWifiConnecteNatif = 'wifi_connected_native';
  static const String _cleWifiSsidNatif = 'wifi_ssid_native';

  /// Message affiché quand la permission GPS est refusée dans le navigateur.
  static const String msgPermissionRefusee =
      'Veuillez autoriser la localisation dans votre navigateur pour marquer votre présence.';

  // ──────────────────────────────────────────────────────────
  // Récupérer le parc — Firebase d'abord, cache local si pas de connexion
  // ──────────────────────────────────────────────────────────
  Future<ParcModel?> _getCurrentPark() async {
    try {
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
      await _sauvegarderParcEnCache(parc);
      return parc;
    } catch (_) {
      return _parcDepuisCache();
    }
  }

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
      await prefs.setString('ssid_bureau_cache', parc.wifiNom);
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────
  // Vérifier via WiFi — lit d'abord le cache natif (Kotlin),
  // puis fallback sur network_info_plus si le cache est vide.
  // ──────────────────────────────────────────────────────────
  Future<bool> estConnecteAuWifiBureau() async {
    if (kIsWeb) return false;
    try {
      final parc = await _getCurrentPark();
      if (parc == null || parc.wifiNom.isEmpty) return false;

      // ── Priorité 1 : cache écrit par WifiZoneReceiver.kt (Kotlin) ──
      final prefs = await SharedPreferences.getInstance();
      final bool wifiConnecteNatif = prefs.getBool(_cleWifiConnecteNatif) ?? false;
      final String ssidNatif = prefs.getString(_cleWifiSsidNatif) ?? '';

      if (wifiConnecteNatif && ssidNatif.isNotEmpty) {
        return ssidNatif == parc.wifiNom;
      }

      if (!wifiConnecteNatif && prefs.containsKey(_cleWifiConnecteNatif)) {
        return false;
      }

      // ── Priorité 2 : network_info_plus (fallback si cache natif absent) ──
      String? wifiName = await _networkInfo
          .getWifiName()
          .timeout(const Duration(seconds: 3));
      if (wifiName == null) return false;
      wifiName = wifiName.replaceAll('"', '');
      return wifiName == parc.wifiNom;
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Vérification GPS avec résultat détaillé
  // Utilisez estDansLaZoneAvecDetails() pour afficher un retour précis,
  // ou estDansLaZone() pour un simple booléen.
  // ──────────────────────────────────────────────────────────

  Future<bool> estDansLaZone() async {
    final result = await estDansLaZoneAvecDetails();
    return result.dansLaZone;
  }

  /// Retourne un résultat détaillé avec un message explicatif.
  Future<ZoneCheckResult> estDansLaZoneAvecDetails() async {
    if (kIsWeb) {
      return _estDansLaZoneWeb();
    }
    return _estDansLaZoneMobile();
  }

  // ── Branche WEB ──────────────────────────────────────────
  Future<ZoneCheckResult> _estDansLaZoneWeb() async {
    try {
      // Demande explicite → déclenche la popup de permission du navigateur
      LocationPermission permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return ZoneCheckResult(
          dansLaZone: false,
          message: msgPermissionRefusee,
        );
      }

      final parc = await _getCurrentPark();
      if (parc == null) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Aucun parc trouvé pour votre compte. Contactez votre administrateur.',
        );
      }

      // Vérifier que les coordonnées du parc sont configurées
      if (parc.latitude == 0 && parc.longitude == 0) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Les coordonnées GPS du parc ne sont pas configurées. Contactez votre administrateur.',
        );
      }

      Position position;
      try {
        // Sur web, pas de timeLimit — on laisse le navigateur gérer le timeout
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw Exception('Délai dépassé pour obtenir la position GPS.'),
        );
      } catch (e) {
        return ZoneCheckResult(
          dansLaZone: false,
          message: 'Impossible d\'obtenir votre position GPS : $e',
        );
      }

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        parc.latitude,
        parc.longitude,
      );

      final distM = distance.round();
      final rayonM = parc.rayon;
      final ok = distance <= rayonM;

      return ZoneCheckResult(
        dansLaZone: ok,
        distanceM: distance,
        rayonM: rayonM,
        message: ok
            ? 'Position confirmée (${distM}m du bureau, rayon : ${rayonM.round()}m) ✅'
            : 'Vous êtes à ${distM}m du bureau (rayon autorisé : ${rayonM.round()}m). Rapprochez-vous du lieu de travail.',
      );
    } catch (e) {
      return ZoneCheckResult(
        dansLaZone: false,
        message: 'Erreur GPS : $e',
      );
    }
  }

  // ── Branche MOBILE (Android) ──────────────────────────────
  Future<ZoneCheckResult> _estDansLaZoneMobile() async {
    try {
      // 1. Service GPS activé ?
      bool serviceActif = await Geolocator.isLocationServiceEnabled();
      if (!serviceActif) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Le GPS est désactivé sur votre appareil. Activez la localisation dans les paramètres.',
        );
      }

      // 2. Vérifier et demander la permission si nécessaire
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Demander la permission à l'utilisateur
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Permission de localisation refusée. Autorisez l\'accès à la position dans les paramètres de l\'application.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Permission de localisation définitivement refusée. Allez dans Paramètres → Application → Autorisations pour l\'activer.',
        );
      }

      // 3. Récupérer le parc
      final parc = await _getCurrentPark();
      if (parc == null) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Aucun parc trouvé pour votre compte. Contactez votre administrateur.',
        );
      }

      // 4. Vérifier que les coordonnées du parc sont configurées
      if (parc.latitude == 0 && parc.longitude == 0) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Les coordonnées GPS du parc ne sont pas configurées. Contactez votre administrateur.',
        );
      }

      Position position;

      // ── Position actuelle GPS (Accuracy HIGH) ──
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (_) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Impossible d\'obtenir votre position GPS. Activez le GPS et réessayez.',
        );
      }

      // Vérifier si la position est trop ancienne (> 5 minutes)
      final age = DateTime.now().difference(position.timestamp);
      if (age.inMinutes > 5) {
        return const ZoneCheckResult(
          dansLaZone: false,
          message:
              'Votre dernière position GPS est trop ancienne (> 5 min). Déplacez-vous à l\'extérieur pour actualiser.',
        );
      }

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        parc.latitude,
        parc.longitude,
      );

      final distM = distance.round();
      final rayonM = parc.rayon;
      final ok = distance <= rayonM;

      return ZoneCheckResult(
        dansLaZone: ok,
        distanceM: distance,
        rayonM: rayonM,
        message: ok
            ? 'Position confirmée (${distM}m du bureau, rayon : ${rayonM.round()}m) ✅'
            : 'Vous êtes à ${distM}m du bureau (rayon autorisé : ${rayonM.round()}m). Rapprochez-vous du lieu de travail.',
      );
    } catch (e) {
      return ZoneCheckResult(
        dansLaZone: false,
        message: 'Erreur GPS inattendue : $e',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Vérification combinée WiFi + GPS
  // WiFi est prioritaire (plus rapide et fiable en intérieur).
  // GPS en fallback si pas de WiFi bureau ou WiFi indisponible.
  // ──────────────────────────────────────────────────────────
  Future<bool> estAuBureau() async {
    final bool wifi = await estConnecteAuWifiBureau();
    if (wifi) return true;
    final bool gps = await estDansLaZone();
    return gps;
  }

  /// Version détaillée — retourne un message explicatif affiché à l'utilisateur.
  Future<ZoneCheckResult> estAuBureauAvecDetails() async {
    // Priorité WiFi
    if (!kIsWeb) {
      final bool wifi = await estConnecteAuWifiBureau();
      if (wifi) {
        return const ZoneCheckResult(
          dansLaZone: true,
          message: 'Connexion WiFi bureau confirmée ✅',
        );
      }
    }
    // Fallback GPS
    return estDansLaZoneAvecDetails();
  }
}