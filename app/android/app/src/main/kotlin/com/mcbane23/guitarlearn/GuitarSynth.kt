package com.mcbane23.guitarlearn

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import java.util.PriorityQueue
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * A tiny real-time guitar synthesizer.
 *
 * Plucked notes use Karplus-Strong string synthesis (a noise burst circulating
 * in a tuned, filtered delay line), so no sound files are needed. Notes are
 * scheduled a little ahead of time by the Dart sequencer, which keeps the sound
 * in step with the neck animation.
 *
 * The audio thread starts on the first note and stops again after some
 * seconds of silence, so the app uses no CPU while nothing is playing.
 */
class GuitarSynth(context: Context) {
    private val sampleRate: Int = run {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager?
        am?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 44100
    }
    private val framesPerBlock: Int = run {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager?
        val native = am?.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull() ?: 256
        native.coerceIn(128, 1024)
    }

    private companion object {
        const val IDLE_SECONDS = 20L
    }

    @Volatile
    var volume: Float = 1f

    private sealed class Command(val enqueuedNanos: Long) {
        class Note(
            val midi: Int,
            val velocity: Float,
            val delayMs: Double,
            val durationMs: Double,
            val string: Int,
            t: Long,
        ) : Command(t)

        class Click(val accent: Boolean, val delayMs: Double, t: Long) : Command(t)
        class StopAll(t: Long) : Command(t)
    }

    private class Scheduled(val frame: Long, val order: Long, val voice: Voice)

    private val commands = ConcurrentLinkedQueue<Command>()
    private val lock = Object()
    private var running = false
    private var shutDown = false

    fun noteOn(midi: Int, velocity: Float, delayMs: Double, durationMs: Double, string: Int) =
        enqueue(Command.Note(midi, velocity, delayMs, durationMs, string, System.nanoTime()))

    fun click(accent: Boolean, delayMs: Double) =
        enqueue(Command.Click(accent, delayMs, System.nanoTime()))

    fun stopAll() = enqueue(Command.StopAll(System.nanoTime()))

    fun shutdown() {
        synchronized(lock) { shutDown = true }
    }

    private fun enqueue(cmd: Command) {
        commands.add(cmd)
        synchronized(lock) {
            if (!running && !shutDown) {
                running = true
                Thread(::audioLoop, "GuitarSynth").start()
            }
        }
    }

    // ---- Audio thread ----------------------------------------------------

    private fun audioLoop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)
        val track = createTrack()
        if (track == null) {
            synchronized(lock) { running = false }
            commands.clear()
            return
        }
        track.play()
        val block = FloatArray(framesPerBlock)
        val voices = ArrayList<Voice>()
        val scheduled = PriorityQueue<Scheduled>(compareBy<Scheduled>({ it.frame }, { it.order }))
        var frame = 0L
        var order = 0L
        var idleFrames = 0L
        try {
            while (true) {
                // Take new commands from the Dart side.
                while (true) {
                    val cmd = commands.poll() ?: break
                    val lateMs = (System.nanoTime() - cmd.enqueuedNanos) / 1e6
                    when (cmd) {
                        is Command.StopAll -> {
                            scheduled.clear()
                            voices.forEach { it.release(fast = true) }
                        }
                        is Command.Note -> {
                            val at = frame + msToFrames(max(0.0, cmd.delayMs - lateMs))
                            val v = PluckVoice(
                                sampleRate, cmd.midi, cmd.velocity, msToFrames(cmd.durationMs), cmd.string,
                            )
                            scheduled.add(Scheduled(at, order++, v))
                        }
                        is Command.Click -> {
                            val at = frame + msToFrames(max(0.0, cmd.delayMs - lateMs))
                            scheduled.add(Scheduled(at, order++, ClickVoice(sampleRate, cmd.accent)))
                        }
                    }
                }

                // Start voices that are due in this block.
                val blockEnd = frame + framesPerBlock
                while (scheduled.isNotEmpty() && scheduled.peek()!!.frame < blockEnd) {
                    val s = scheduled.poll()!!
                    val v = s.voice
                    v.startOffset = (s.frame - frame).toInt().coerceIn(0, framesPerBlock - 1)
                    if (v.string > 0) {
                        // A real string can only ring one note at a time.
                        voices.forEach { if (it.string == v.string) it.release(fast = true) }
                    }
                    voices.add(v)
                }

                block.fill(0f)
                val it = voices.iterator()
                while (it.hasNext()) {
                    val v = it.next()
                    v.render(block)
                    if (v.finished) it.remove()
                }
                val gain = volume * 0.35f
                for (i in block.indices) {
                    val x = block[i] * gain
                    block[i] = x / (1f + abs(x)) // soft clip
                }
                track.write(block, 0, block.size, AudioTrack.WRITE_BLOCKING)
                frame = blockEnd

                if (voices.isEmpty() && scheduled.isEmpty()) {
                    idleFrames += framesPerBlock
                    // Keep the track open for a while: starting it again costs
                    // tens of milliseconds, which would delay the first note
                    // after every short pause (free play, picking chords).
                    if (idleFrames > sampleRate * IDLE_SECONDS) {
                        synchronized(lock) {
                            if (commands.isEmpty() || shutDown) {
                                running = false
                                return
                            }
                        }
                        idleFrames = 0
                    }
                } else {
                    idleFrames = 0
                }
                if (shutDown) {
                    synchronized(lock) { running = false }
                    return
                }
            }
        } finally {
            try {
                track.stop()
            } catch (_: IllegalStateException) {
            }
            track.release()
        }
    }

    private fun msToFrames(ms: Double): Long = (ms * sampleRate / 1000.0).roundToLong()

    private fun createTrack(): AudioTrack? {
        return try {
            val minBytes = AudioTrack.getMinBufferSize(
                sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT,
            )
            val builder = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(max(minBytes, framesPerBlock * 4 * 4))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                builder.setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            }
            builder.build()
        } catch (e: Exception) {
            null
        }
    }
}

private abstract class Voice {
    var startOffset = 0
    open val string: Int = 0
    var finished = false
        protected set

    abstract fun render(out: FloatArray)
    abstract fun release(fast: Boolean)
}

/** Karplus-Strong plucked string with fractional-delay tuning. */
private class PluckVoice(
    private val sampleRate: Int,
    midi: Int,
    velocity: Float,
    private val durationFrames: Long,
    override val string: Int,
) : Voice() {
    private val freq = 440.0 * 2.0.pow((midi - 69) / 12.0)
    private val delay: FloatArray
    private var idx = 0
    private var prev = 0f
    private val apC: Float
    private var apIn = 0f
    private var apOut = 0f
    private var loss: Float
    private val releaseLoss: Float
    private val fastLoss: Float
    private var age = 0L
    private var releasedAt = -1L
    private val maxAge: Long

    init {
        // Loop delay = N samples + 0.5 (averaging filter) + d (all-pass).
        val period = sampleRate / freq
        var n = floor(period - 0.5).toInt()
        var d = period - 0.5 - n
        if (d < 0.1) {
            n -= 1
            d += 1.0
        }
        n = max(n, 2)
        apC = ((1 - d) / (1 + d)).toFloat()
        delay = FloatArray(n)

        // Excitation: filtered noise; harder plucks are brighter.
        val v = velocity.coerceIn(0.05f, 1f)
        val brightness = 0.25f + 0.6f * v
        var lp = 0f
        var mean = 0f
        for (i in 0 until n) {
            lp += brightness * (Random.nextFloat() * 2f - 1f - lp)
            delay[i] = lp
            mean += lp
        }
        mean /= n
        // Pluck position (about 1/7 of the string) shapes the tone like a real pick.
        val p = max(1, (n / 7.0).roundToInt())
        val shaped = FloatArray(n) { i -> delay[i] - mean - 0.5f * (delay[(i - p + n) % n] - mean) }
        var peak = 1e-6f
        for (x in shaped) peak = max(peak, abs(x))
        for (i in 0 until n) delay[i] = shaped[i] / peak * v

        val t60 = (4.0 * sqrt(110.0 / freq)).coerceIn(0.8, 5.0)
        loss = lossFor(t60)
        releaseLoss = lossFor(0.25)
        fastLoss = lossFor(0.04)
        maxAge = ((t60 + 0.3) * sampleRate).toLong()
    }

    private fun lossFor(t60: Double): Float = 10.0.pow(-3.0 / (t60 * freq)).toFloat()

    override fun release(fast: Boolean) {
        if (releasedAt < 0 || fast) {
            releasedAt = age
            loss = if (fast) fastLoss else min(loss, releaseLoss)
        }
    }

    override fun render(out: FloatArray) {
        val n = delay.size
        for (i in startOffset until out.size) {
            if (age == durationFrames) release(fast = false)
            val x = delay[idx]
            val y = 0.5f * (x + prev) * loss
            prev = x
            val ap = apC * y + apIn - apC * apOut
            apIn = y
            apOut = ap
            delay[idx] = ap
            idx = if (idx + 1 == n) 0 else idx + 1
            out[i] += x
            age++
        }
        startOffset = 0
        val releasedLongEnough = releasedAt >= 0 && age - releasedAt > sampleRate / 2
        if (age > maxAge || releasedLongEnough) finished = true
    }
}

/** Short metronome click. */
private class ClickVoice(private val sampleRate: Int, accent: Boolean) : Voice() {
    private val freq = if (accent) 2000.0 else 1400.0
    private val amp = if (accent) 0.9f else 0.6f
    private val length = (0.05 * sampleRate).toInt()
    private var t = 0

    override fun release(fast: Boolean) {
        finished = true
    }

    override fun render(out: FloatArray) {
        if (finished) return
        for (i in startOffset until out.size) {
            if (t >= length) {
                finished = true
                break
            }
            val s = t.toDouble() / sampleRate
            out[i] += (amp * exp(-s / 0.01) * sin(2 * PI * freq * s)).toFloat()
            t++
        }
        startOffset = 0
    }
}
