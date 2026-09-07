import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailService {
  static const String _serviceId = 'service_my2kwph';
  static const String _templateId = 'template_1x73wi4';
  static const String _publicKey = 'TZS9LBpr_wp-c2mOr';
  static const String _destinataire = 'etondji79@gmail.com';

  static Future<bool> envoyerRapportHebdomadaire({
    required String semaine,
    required String periode,
    required int nombrePresents,
    required int nombreManuels,
    required int nombreAbsents,
  }) async {
    try {
      final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'origin': 'http://localhost',
        },
        body: jsonEncode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _publicKey,
          'template_params': {
            'semaine': semaine,
            'periode': periode,
            'nombre_presents': nombrePresents.toString(),
            'nombre_manuels': nombreManuels.toString(),
            'nombre_absents': nombreAbsents.toString(),
            'to_email': _destinataire,
          },
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}