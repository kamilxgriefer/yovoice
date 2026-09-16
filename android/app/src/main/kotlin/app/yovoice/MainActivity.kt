package app.yovoice

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "app.yo_voice/voice_session"
        private const val DIRECT_CALL_PIP_CHANNEL = "app.yovoice/direct_call_pip"
        private const val DIRECT_VIDEO_AUDIO_CHANNEL = "app.yovoice/direct_video_audio"
    }

    private var directCallPictureInPicture: DirectCallPictureInPictureController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val pipChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DIRECT_CALL_PIP_CHANNEL,
        )
        directCallPictureInPicture = DirectCallPictureInPictureController(this, pipChannel)
        pipChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> result.success(
                    directCallPictureInPicture?.setActive(call.arguments) ?: false,
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DIRECT_VIDEO_AUDIO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareMoviePlayback" -> result.success(prepareMoviePlaybackAudio())
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Started from the join path while the app is still in the
                    // foreground: Android 12+ refuses a background start.
                    "start" -> {
                        val intent = Intent(this, VoiceSessionService::class.java).apply {
                            action = VoiceSessionService.ACTION_START
                            putExtra(
                                VoiceSessionService.EXTRA_TITLE,
                                call.argument<String>("title"),
                            )
                            putExtra(
                                VoiceSessionService.EXTRA_BODY,
                                call.argument<String>("body"),
                            )
                            putExtra(
                                VoiceSessionService.EXTRA_CAN_PUBLISH,
                                call.argument<Boolean>("canPublish") ?: false,
                            )
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                ContextCompat.startForegroundService(this, intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (error: Exception) {
                            // The call still works without the service; it just
                            // will not survive being backgrounded.
                            result.success(false)
                        }
                    }
                    "stop" -> {
                        try {
                            stopService(Intent(this, VoiceSessionService::class.java))
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "setScreenShareActive" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        // Applied in-process on the running voice service, so
                        // this reply follows startForeground. There is no
                        // Intent path: it could restart a stopped service, be
                        // refused as a background start, or reply before the
                        // mediaProjection type exists (Android 14+).
                        result.success(VoiceSessionService.running?.setScreenShareActive(active) ?: !active)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Leaves WebRTC's communication route before a user-started chat video.
     *
     * The Dart realtime-session registry guarantees this is never called while
     * a private call or server voice session still owns process-wide audio.
     * video_player acquires media focus itself, so this bridge resets only the
     * stale communication mode/device instead of abandoning another player's
     * focus with an unrelated listener token.
     */
    private fun prepareMoviePlaybackAudio(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return false
        // Before Android 12 the audio mode is process-global. MODE_IN_CALL is
        // a telephony call owned by another party, which a chat video must
        // never reset to MODE_NORMAL or reroute.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && audioManager.mode == AudioManager.MODE_IN_CALL) return false
        return try {
            audioManager.mode = AudioManager.MODE_NORMAL
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            } else {
                @Suppress("DEPRECATION")
                audioManager.stopBluetoothSco()
                @Suppress("DEPRECATION")
                run { audioManager.isBluetoothScoOn = false }
                @Suppress("DEPRECATION")
                run { audioManager.isSpeakerphoneOn = false }
            }
            true
        } catch (_: SecurityException) {
            false
        } catch (_: IllegalStateException) {
            false
        }
    }

    override fun onResume() {
        super.onResume()
        directCallPictureInPicture?.onResume()
    }

    override fun onUserLeaveHint() {
        directCallPictureInPicture?.onUserLeaveHint()
        super.onUserLeaveHint()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        @Suppress("DEPRECATION")
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        directCallPictureInPicture?.onPictureInPictureModeChanged(
            isInPictureInPictureMode,
        )
    }

    override fun onDestroy() {
        directCallPictureInPicture?.release()
        directCallPictureInPicture = null
        super.onDestroy()
    }
}
