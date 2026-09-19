package com.tonnom.adnpresence

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class WifiZoneReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "WifiZoneReceiver"
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_DEJA_MARQUE    = "flutter.deja_marque"
        const val KEY_ETAT_AU_BUREAU = "flutter.etat_au_bureau"
        const val KEY_SSID_BUREAU    = "flutter.ssid_bureau_cache"
        const val KEY_BSSID_BUREAU   = "flutter.bssid_bureau_cache"
        const val KEY_MOUVEMENTS     = "flutter.mouvements_en_attente"
        const val KEY_MODE_QR        = "flutter.mode_qr"
        const val NOTIFICATION_ID    = 1000
        const val CHANNEL_ID         = "presence_channel"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "Broadcast recu : $action")

        when (action) {
            WifiManager.WIFI_STATE_CHANGED_ACTION -> {
                val state = intent.getIntExtra(WifiManager.EXTRA_WIFI_STATE, WifiManager.WIFI_STATE_UNKNOWN)
                if (state == WifiManager.WIFI_STATE_DISABLED || state == WifiManager.WIFI_STATE_DISABLING) {
                    Log.d(TAG, "WiFi desactive -> sortie")
                    processNetworkChange(context, connected = false, bssidFromIntent = null)
                }
            }

            WifiManager.NETWORK_STATE_CHANGED_ACTION -> {
                @Suppress("DEPRECATION")
                val networkInfo = intent.getParcelableExtra<android.net.NetworkInfo>(WifiManager.EXTRA_NETWORK_INFO)
                val bssid = intent.getStringExtra(WifiManager.EXTRA_BSSID)
                if (networkInfo?.isConnected == true && bssid != null) {
                    Log.d(TAG, "WiFi connecte, BSSID=$bssid -> retour potentiel")
                    android.os.Handler(context.mainLooper).postDelayed({
                        processNetworkChange(context, connected = true, bssidFromIntent = bssid)
                    }, 1000)
                } else if (networkInfo?.isConnected == false) {
                    processNetworkChange(context, connected = false, bssidFromIntent = null)
                }
            }

            @Suppress("DEPRECATION")
            ConnectivityManager.CONNECTIVITY_ACTION -> {
                val isConnected = isWifiCurrentlyConnected(context)
                processNetworkChange(context, connected = isConnected, bssidFromIntent = null)
            }
        }
    }

    fun forceCheck(context: Context) {
        Log.d(TAG, "forceCheck() appele")
        val connected = isWifiCurrentlyConnected(context)
        processNetworkChange(context, connected = connected, bssidFromIntent = null)
    }

    private fun processNetworkChange(context: Context, connected: Boolean, bssidFromIntent: String?) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val modeQr = prefs.getBoolean(KEY_MODE_QR, false)
        val dejaMarque = prefs.getBoolean(KEY_DEJA_MARQUE, false)
        if (modeQr || !dejaMarque) {
            Log.d(TAG, "Surveillance inactive (modeQr=$modeQr, dejaMarque=$dejaMarque)")
            return
        }

        if (!prefs.contains(KEY_ETAT_AU_BUREAU)) {
            Log.d(TAG, "Initialisation etat_au_bureau=$connected")
            prefs.edit().putBoolean(KEY_ETAT_AU_BUREAU, connected).apply()
            return
        }

        val dernierEtat = prefs.getBoolean(KEY_ETAT_AU_BUREAU, false)
        val bssidBureau = prefs.getString(KEY_BSSID_BUREAU, "")
        val ssidBureau  = prefs.getString(KEY_SSID_BUREAU, "")

        val estAuBureau = if (connected) {
            when {
                bssidFromIntent != null && !bssidBureau.isNullOrEmpty() -> {
                    val match = bssidFromIntent == bssidBureau
                    Log.d(TAG, "Comparaison BSSID: intent=$bssidFromIntent bureau=$bssidBureau -> $match")
                    match
                }
                bssidFromIntent != null && bssidBureau.isNullOrEmpty() -> {
                    val currentSsid = getSsidFromWifiManager(context)
                    if (currentSsid != null && currentSsid == ssidBureau) {
                        Log.d(TAG, "Apprentissage BSSID bureau : $bssidFromIntent")
                        prefs.edit().putString(KEY_BSSID_BUREAU, bssidFromIntent).apply()
                        true
                    } else false
                }
                !ssidBureau.isNullOrEmpty() -> {
                    val currentSsid = getSsidFromWifiManager(context)
                    val match = currentSsid != null && currentSsid == ssidBureau
                    if (match && bssidBureau.isNullOrEmpty()) {
                        val b = getBssidFromWifiManager(context)
                        if (!b.isNullOrEmpty()) {
                            Log.d(TAG, "Apprentissage BSSID (via SSID) : $b")
                            prefs.edit().putString(KEY_BSSID_BUREAU, b).apply()
                        }
                    }
                    Log.d(TAG, "Comparaison SSID: current=$currentSsid bureau=$ssidBureau -> $match")
                    match
                }
                else -> false
            }
        } else false

        val now = Date()
        val formattedTime = SimpleDateFormat("HH'h'mm", Locale.FRANCE).apply {
            timeZone = TimeZone.getDefault()
        }.format(now)

        when {
            dernierEtat && !estAuBureau -> {
                Log.d(TAG, "SORTIE detectee")
                prefs.edit().putBoolean(KEY_ETAT_AU_BUREAU, false).apply()
                addMouvement(prefs, "sortie", now)
                updateNotification(context, "Sortie detectee a $formattedTime")
            }
            !dernierEtat && estAuBureau -> {
                Log.d(TAG, "RETOUR detecte")
                prefs.edit().putBoolean(KEY_ETAT_AU_BUREAU, true).apply()
                addMouvement(prefs, "retour", now)
                updateNotification(context, "Retour detecte a $formattedTime")
            }
            else -> {
                val text = if (estAuBureau) "Presence enregistree aujourd'hui" else "Hors zone - surveillance active"
                updateNotification(context, text)
            }
        }
    }

    private fun isWifiCurrentlyConnected(context: Context): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
            } else {
                @Suppress("DEPRECATION")
                cm.activeNetworkInfo?.type == ConnectivityManager.TYPE_WIFI && cm.activeNetworkInfo?.isConnected == true
            }
        } catch (e: Exception) { false }
    }

    @Suppress("DEPRECATION")
    private fun getSsidFromWifiManager(context: Context): String? {
        return try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val raw = wm.connectionInfo?.ssid ?: return null
            val cleaned = raw.removePrefix("\"").removeSuffix("\"")
            if (cleaned.isEmpty() || cleaned == "<unknown ssid>" || cleaned == "0x") null else cleaned
        } catch (e: Exception) { null }
    }

    @Suppress("DEPRECATION")
    private fun getBssidFromWifiManager(context: Context): String? {
        return try {
            val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val bssid = wm.connectionInfo?.bssid ?: return null
            if (bssid == "02:00:00:00:00:00" || bssid.isBlank()) null else bssid
        } catch (e: Exception) { null }
    }

    private fun addMouvement(prefs: android.content.SharedPreferences, type: String, date: Date) {
        try {
            val raw = prefs.getString(KEY_MOUVEMENTS, "[]") ?: "[]"
            val jsonArray = JSONArray(raw)
            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }
            val obj = JSONObject()
            obj.put("type", type)
            obj.put("heure", isoFormat.format(date))
            jsonArray.put(obj)
            prefs.edit().putString(KEY_MOUVEMENTS, jsonArray.toString()).apply()
            Log.d(TAG, "Mouvement ajoute : $type")
        } catch (e: Exception) {
            Log.e(TAG, "Erreur ajout mouvement", e)
        }
    }

    @SuppressLint("MissingPermission")
    private fun updateNotification(context: Context, text: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(CHANNEL_ID, "PresenceApp", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Surveillance de presence"
                }
                (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .createNotificationChannel(channel)
            }
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            val pendingIntent = launchIntent?.let {
                PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            }
            val appInfo = context.packageManager.getApplicationInfo(context.packageName, 0)
            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(appInfo.icon)
                .setContentTitle("PresenceApp")
                .setContentText(text)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
            pendingIntent?.let { builder.setContentIntent(it) }
            NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
        } catch (e: Exception) {
            Log.e(TAG, "Erreur notification", e)
        }
    }
}
