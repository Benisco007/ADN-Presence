package com.tonnom.adnpresence

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.tonnom.adnpresence/wifi_check"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Démarrer le WifiWatcherService qui vit dans le process et
        // survit au swipe de l'app (START_STICKY).
        startService(Intent(this, WifiWatcherService::class.java))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "checkNow") {
                val intent = Intent(this, WifiWatcherService::class.java).apply {
                    action = WifiWatcherService.ACTION_CHECK_NOW
                }
                startService(intent)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
