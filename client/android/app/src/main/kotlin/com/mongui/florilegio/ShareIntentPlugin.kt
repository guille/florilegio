package com.mongui.florilegio

import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Handles ACTION_SEND intents and bridges them to Flutter via MethodChannel.
 *
 * Dart side calls `getSharedText` to get the initial shared text (if the app
 * was launched via share sheet). For shares arriving while the app is already
 * running, `onNewIntent` pushes them to Dart via `invokeMethod("onSharedText")`.
 */
class ShareIntentPlugin(private val messenger: BinaryMessenger) {
    companion object {
        private const val CHANNEL = "com.mongui.florilegio/share"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    fun register(getIntent: () -> Intent?) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> result.success(extractSharedText(getIntent()))
                else -> result.notImplemented()
            }
        }
    }

    fun onNewIntent(intent: Intent) {
        val text = extractSharedText(intent)
        if (text != null) {
            channel.invokeMethod("onSharedText", text)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            // Clear to prevent re-processing on hot restart
            intent.removeExtra(Intent.EXTRA_TEXT)
            return text
        }
        return null
    }
}
