package app.yo_voice

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
// The Gradle namespace is app.yovoice while this file lives in app.yo_voice,
// so R must be imported explicitly.
import app.yovoice.R

/**
 * Keeps a voice room or a private call alive while the app is in the
 * background.
 *
 * Without a foreground service Android silences a backgrounded process's
 * microphone and freezes the process once it is cached, which is why a call
 * survived one party minimising the app but collapsed when both did: with no
 * audio flowing in either direction, both processes were frozen and both
 * LiveKit participants timed out.
 *
 * The service type follows what the session may actually do: a participant
 * allowed to publish needs `microphone`, a listener only needs
 * `mediaPlayback`. Requesting `microphone` without a granted RECORD_AUDIO is a
 * SecurityException, so that case falls back to `mediaPlayback` instead of
 * taking the app down.
 */
class VoiceSessionService : Service() {
    companion object {
        const val ACTION_START = "app.yo_voice.voice_session.START"
        const val ACTION_STOP = "app.yo_voice.voice_session.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_CAN_PUBLISH = "canPublish"

        private const val CHANNEL_ID = "yovoice_voice_session"
        private const val NOTIFICATION_ID = 4711
        private const val TAG = "VoiceSessionService"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> startInForeground(intent)
        }
        // The Dart side owns the lifetime: it starts the service when a
        // session connects and stops it on disconnect. Never restart on our
        // own — a resurrected notification with no call behind it is worse
        // than no notification.
        return START_NOT_STICKY
    }

    private fun startInForeground(intent: Intent?) {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: getString(R.string.voice_session_title)
        val body = intent?.getStringExtra(EXTRA_BODY) ?: getString(R.string.voice_session_body)
        val wantsMicrophone = intent?.getBooleanExtra(EXTRA_CAN_PUBLISH, false) ?: false
        val micGranted = ContextCompat.checkSelfPermission(
            this,
            android.Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

        ensureChannel()
        val notification = buildNotification(title, body)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val type = if (wantsMicrophone && micGranted) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                } else {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                }
                startForeground(NOTIFICATION_ID, notification, type)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: Exception) {
            // A refused foreground start (OEM policy, a start that raced the
            // app going to the background) must never crash the call.
            Log.w(TAG, "Could not start the voice session service", error)
            stopSelf()
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.voice_session_channel_name),
            // Low: the ongoing row must be visible and dismissible only by
            // leaving the call, never a sound or a heads-up interruption.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.voice_session_channel_description)
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, body: String): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_sys_speakerphone)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setContentIntent(pending)
            .build()
    }
}
