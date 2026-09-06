package app.yo_voice

import android.content.Intent
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "app.yo_voice/voice_session"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    else -> result.notImplemented()
                }
            }
    }
}
