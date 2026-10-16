package com.otclient

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * OurTibia (16.10.2026): keeps the game process running while the app is in the background
 * (another app opened, screen off). Without it Android freezes the process, the connection
 * stops answering and the server logs the character out. Shows a silent ongoing notification.
 */
class KeepAliveService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        goForeground()
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "OurTibia:game").apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) { }
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_HIGH_PERF else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wm.createWifiLock(mode, "OurTibia:game").apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) { }
    }

    private fun goForeground() {
        val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        val pi = PendingIntent.getActivity(this, 0, open, flags)
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("OurTibia")
            .setContentText("The game keeps running - you stay logged in.")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pi)
            .build()
        val type = if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        } catch (_: Exception) {
            // not allowed right now (e.g. started from the background) - the app still works,
            // it only may be paused by the system in the background
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // every startForegroundService() must be answered with startForeground()
        goForeground()
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // the player swiped the app away: stop
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        try { wakeLock?.release() } catch (_: Exception) { }
        try { wifiLock?.release() } catch (_: Exception) { }
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                val ch = NotificationChannel(CHANNEL, "Game running", NotificationManager.IMPORTANCE_LOW)
                ch.description = "Keeps OurTibia connected while the app is in the background"
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
        }
    }

    companion object {
        private const val CHANNEL = "ourtibia_running"
        private const val NOTIFICATION_ID = 7171

        fun start(context: Context) {
            val i = Intent(context, KeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
            } catch (_: Exception) { }
        }

        fun stop(context: Context) {
            try { context.stopService(Intent(context, KeepAliveService::class.java)) } catch (_: Exception) { }
        }
    }
}
