package com.tonnom.adnpresence

import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.util.Log

class WifiWatcherService : Service() {

    private var receiver: WifiZoneReceiver? = null

    companion object {
        private const val TAG = "WifiWatcherService"
        const val ACTION_CHECK_NOW = "com.tonnom.adnpresence.CHECK_NOW"
    }

    override fun onCreate() {
        super.onCreate()
        registerWifiReceiver()
        Log.d(TAG, "WifiWatcherService démarré — receiver enregistré")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Déclenchement explicite depuis Dart (ex: après marquage de présence)
        if (intent?.action == ACTION_CHECK_NOW) {
            Log.d(TAG, "CHECK_NOW reçu — vérification immédiate du statut WiFi")
            receiver?.forceCheck(this)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterWifiReceiver()
        super.onDestroy()
        Log.d(TAG, "WifiWatcherService arrêté — receiver retiré")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerWifiReceiver() {
        if (receiver != null) return
        receiver = WifiZoneReceiver()
        val filter = IntentFilter().apply {
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION)
            addAction(WifiManager.NETWORK_STATE_CHANGED_ACTION)
            @Suppress("DEPRECATION")
            addAction(ConnectivityManager.CONNECTIVITY_ACTION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        // Vérification immédiate au démarrage
        receiver?.forceCheck(this)
    }

    private fun unregisterWifiReceiver() {
        try {
            receiver?.let { unregisterReceiver(it) }
        } catch (_: Exception) {}
        receiver = null
    }
}
