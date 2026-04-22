package com.mongui.florilegio

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var sharePlugin: ShareIntentPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharePlugin = ShareIntentPlugin(flutterEngine.dartExecutor.binaryMessenger)
        sharePlugin?.register { intent }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharePlugin?.onNewIntent(intent)
    }
}
