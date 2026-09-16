package app.yovoice

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.MethodChannel

/**
 * Owns system PiP eligibility for the one Flutter Activity.
 *
 * Dart arms this only after a 1:1 video call is connected and a remote camera
 * track is subscribed. Audio calls, ringing calls and server sessions never
 * make the Activity eligible for automatic PiP.
 */
internal class DirectCallPictureInPictureController(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    private var active = false
    private var inPictureInPicture = false
    private var aspectWidth = 16
    private var aspectHeight = 9

    fun setActive(arguments: Any?): Boolean {
        val values = arguments as? Map<*, *> ?: return false
        val requested = values["active"] == true
        if (!requested) {
            active = false
            updateParams()
            if (inPictureInPicture) {
                // Android exposes no public "exit PiP but keep this Activity"
                // API. Moving the task behind Home is the non-destructive way
                // to remove a completed-call overlay; reopening YO Voice then
                // restores the same task instead of cold-starting it.
                activity.moveTaskToBack(false)
            }
            return isSupported()
        }
        if (!isSupported()) {
            active = false
            return false
        }
        val trackId = (values["trackId"] as? String)?.trim().orEmpty()
        if (trackId.isEmpty()) {
            active = false
            updateParams()
            return false
        }
        val width = (values["width"] as? Number)?.toInt() ?: 16
        val height = (values["height"] as? Number)?.toInt() ?: 9
        if (isAllowedAspectRatio(width, height)) {
            aspectWidth = width
            aspectHeight = height
        } else {
            aspectWidth = 16
            aspectHeight = 9
        }
        active = true
        updateParams()
        return true
    }

    fun onResume() {
        updateParams()
    }

    fun onUserLeaveHint() {
        if (!active || !isSupported()) return
        if (Build.VERSION.SDK_INT in Build.VERSION_CODES.O until Build.VERSION_CODES.S) {
            try {
                @Suppress("DEPRECATION")
                activity.enterPictureInPictureMode(buildParams())
            } catch (_: IllegalStateException) {
                // The Activity may already be stopping after a rapid hang-up.
            }
        }
    }

    fun onPictureInPictureModeChanged(inPictureInPicture: Boolean) {
        this.inPictureInPicture = inPictureInPicture
        channel.invokeMethod("pictureInPictureChanged", inPictureInPicture)
    }

    fun release() {
        active = false
        inPictureInPicture = false
        updateParams()
    }

    private fun isSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun updateParams() {
        if (!isSupported()) return
        try {
            activity.setPictureInPictureParams(buildParams())
        } catch (_: IllegalArgumentException) {
            aspectWidth = 16
            aspectHeight = 9
            activity.setPictureInPictureParams(buildParams())
        } catch (_: IllegalStateException) {
            // A destroyed Activity no longer accepts PiP configuration.
        }
    }

    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(aspectWidth, aspectHeight))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder
                .setAutoEnterEnabled(active)
                .setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    companion object {
        /** Android permits PiP ratios from 1:2.39 through 2.39:1. */
        internal fun isAllowedAspectRatio(width: Int, height: Int): Boolean {
            if (width <= 0 || height <= 0) return false
            val ratio = width.toDouble() / height.toDouble()
            return ratio in (1.0 / 2.39)..2.39
        }
    }
}
