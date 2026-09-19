import 'package:flutter/services.dart';

class WifiCheckService {
  static const _channel = MethodChannel('com.tonnom.adnpresence/wifi_check');

  static Future<void> checkNow() async {
    try {
      await _channel.invokeMethod('checkNow');
    } catch (_) {}
  }
}
