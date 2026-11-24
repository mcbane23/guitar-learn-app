package com.mcbane23.guitarlearn

import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var synth: GuitarSynth? = null
    private var folders: SongFolders? = null
    private var updates: AppUpdate? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val s = GuitarSynth(this)
        synth = s
        folders = SongFolders(this, flutterEngine.dartExecutor.binaryMessenger)
        updates = AppUpdate(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "guitar_learn/synth")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val notes = call.argument<List<Map<String, Any>>>("notes") ?: emptyList()
                        for (n in notes) {
                            s.noteOn(
                                midi = (n["midi"] as Number).toInt(),
                                velocity = (n["velocity"] as Number).toFloat(),
                                delayMs = (n["delayMs"] as Number).toDouble(),
                                durationMs = (n["durationMs"] as Number).toDouble(),
                                string = (n["string"] as Number).toInt(),
                            )
                        }
                        result.success(null)
                    }
                    "click" -> {
                        s.click(
                            accent = call.argument<Boolean>("accent") ?: false,
                            delayMs = call.argument<Number>("delayMs")?.toDouble() ?: 0.0,
                        )
                        result.success(null)
                    }
                    "stopAll" -> {
                        s.stopAll()
                        result.success(null)
                    }
                    "setVolume" -> {
                        s.volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Keeps the screen (and the TV) from going dark while a song is open:
        // a beginner often watches the neck for a long time without touching anything.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "guitar_learn/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (folders?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onPause() {
        super.onPause()
        synth?.stopAll()
    }

    override fun onDestroy() {
        synth?.shutdown()
        synth = null
        folders?.shutdown()
        folders = null
        super.onDestroy()
    }
}
