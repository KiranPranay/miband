package com.example.band

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Adds a headless trigger for the hardware test session so the loop can be driven
 * over adb with no manual taps:
 *
 *   adb shell am start -n com.example.band/.MainActivity --ez run_hwtest true
 *
 * Cold start: the launch intent's `run_hwtest` extra is stashed and handed to Dart
 * when it calls `checkLaunchTrigger`. Hot (already running): `onNewIntent` pushes
 * `runHardwareTest` straight to Dart. See docs/reverse-engineering/capture-logs.md.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "band/hwtest"
    private var channel: MethodChannel? = null
    private var pending = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkLaunchTrigger" -> {
                    val p = pending
                    pending = false
                    result.success(p)
                }
                else -> result.notImplemented()
            }
        }
        if (intent?.getBooleanExtra("run_hwtest", false) == true) {
            pending = true
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("run_hwtest", false)) {
            val c = channel
            if (c != null) {
                c.invokeMethod("runHardwareTest", null)
            } else {
                pending = true
            }
        }
    }
}
