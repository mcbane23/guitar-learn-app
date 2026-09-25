package com.mcbane23.guitarlearn

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var synth: GuitarSynth? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val s = GuitarSynth(this)
        synth = s
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
    }

    override fun onPause() {
        super.onPause()
        synth?.stopAll()
    }

    override fun onDestroy() {
        synth?.shutdown()
        synth = null
        super.onDestroy()
    }
}
