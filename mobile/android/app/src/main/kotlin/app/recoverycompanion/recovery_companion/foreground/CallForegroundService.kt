package app.recoverycompanion.recovery_companion.foreground

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import app.recoverycompanion.recovery_companion.MainActivity

/**
 * Keeps the live call's mic + socket alive through screen lock and
 * backgrounding, per DESIGN.md §3.9. Without this, Android suspends mic
 * access within seconds of the app losing foreground visibility, silently
 * killing the call the person is relying on.
 *
 * Deliberately minimal for M2: start/stop only, declared with
 * `foregroundServiceType="microphone"` in the manifest. The notification's
 * "end call" action stops this service directly (so the mic/foreground
 * privilege is released immediately either way); it does not yet reach back
 * into the Dart session to tear down the Live API socket/UI state — that
 * belongs to the (out-of-scope-here) crisis-screen UI milestone, which owns
 * `LiveSessionController.endCall()` and can add an `EventChannel` from this
 * service if it wants the notification's end-call tap to drive it directly.
 *
 * Camera-while-backgrounded is NOT handled by this service on purpose: per
 * §3.9's last paragraph, stock Android does not allow background camera
 * access from a non-visible Activity regardless of foreground-service type,
 * so camera goes dark on screen lock no matter what this service declares.
 * That is a Dart-/session-side concern (sending a director-note that the
 * camera is unavailable), not something this service can or should paper
 * over.
 */
class CallForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "live_call_channel"
        const val NOTIFICATION_ID = 4201
        const val ACTION_END_CALL = "app.recoverycompanion.recovery_companion.action.END_CALL"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannelIfNeeded()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_END_CALL) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundCompat(buildNotification())
        // Not START_STICKY: if the OS kills this process, the Live API
        // socket died with it — the Dart layer, not this service, decides
        // whether to reconnect.
        return START_NOT_STICKY
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Live call",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while you're on a live call with Recovery Companion."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val openPendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        val openPendingIntent =
            PendingIntent.getActivity(this, 0, openIntent, openPendingFlags)

        val endCallIntent = Intent(this, CallForegroundService::class.java).apply {
            action = ACTION_END_CALL
        }
        val endCallPendingIntent =
            PendingIntent.getService(this, 0, endCallIntent, openPendingFlags)

        // Channel-aware constructor requires API 26+ (minSdk here is 24) —
        // fall back to the deprecated single-arg constructor below that.
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Recovery Companion — still on the line")
            .setContentText("Tap to return to the call.")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(openPendingIntent)
            .addAction(0, "End call", endCallPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
