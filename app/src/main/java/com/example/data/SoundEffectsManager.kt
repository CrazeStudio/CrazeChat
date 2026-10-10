package com.example.data

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * High-performance sound effects and haptics engine for CrazeChat.
 * Generates pristine studio-grade PCM tones in-memory (no external files needed)
 * and plays them with near-zero latency.
 */
class SoundEffectsManager private constructor(private val context: Context) {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val userPrefs = UserPreferences(context)

    private val vibrator: Vibrator? by lazy {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
        } catch (e: Exception) {
            null
        }
    }

    // Cached sound buffers (PCM 16-bit mono @ 44100Hz)
    private val sendSoundBuffer: ByteArray by lazy { generateChirp(startFreq = 580f, endFreq = 920f, durationMs = 85) }
    private val receiveSoundBuffer: ByteArray by lazy { generateDoubleChime(freq1 = 880f, freq2 = 1320f, durationMs = 130) }
    private val deleteSoundBuffer: ByteArray by lazy { generateDescendPop(startFreq = 420f, endFreq = 160f, durationMs = 70) }
    private val pinSoundBuffer: ByteArray by lazy { generateCrystalPing(freq = 1450f, durationMs = 95) }
    private val clickSoundBuffer: ByteArray by lazy { generateTick(freq = 1000f, durationMs = 25) }

    fun playMessageSent() {
        playCachedSound(sendSoundBuffer)
        vibrate(20, 160)
    }

    fun playMessageReceived() {
        playCachedSound(receiveSoundBuffer)
        vibrate(35, 200)
    }

    fun playMessageDeleted() {
        playCachedSound(deleteSoundBuffer)
        vibrate(25, 120)
    }

    fun playMessagePinned() {
        playCachedSound(pinSoundBuffer)
        vibrate(30, 220)
    }

    fun playClick() {
        playCachedSound(clickSoundBuffer)
        vibrate(12, 100)
    }

    private fun playCachedSound(buffer: ByteArray) {
        scope.launch {
            try {
                val isSoundEnabled = userPrefs.soundEffectsEnabledFlow.first()
                if (!isSoundEnabled) return@launch

                val sampleRate = 44100
                val minBufferSize = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
                )
                val bufferSize = maxOf(buffer.size, minBufferSize)

                val audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()

                val audioFormat = AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()

                val track = AudioTrack.Builder()
                    .setAudioAttributes(audioAttributes)
                    .setAudioFormat(audioFormat)
                    .setBufferSizeInBytes(bufferSize)
                    .setTransferMode(AudioTrack.MODE_STATIC)
                    .build()

                track.write(buffer, 0, buffer.size)
                track.play()

                // Release track after playback completes
                val playDurationMs = (buffer.size * 1000L) / (sampleRate * 2)
                kotlinx.coroutines.delay(playDurationMs + 50)
                track.stop()
                track.release()
            } catch (e: Exception) {
                Log.w("SoundEffectsManager", "Error playing sound: ${e.message}")
            }
        }
    }

    private fun vibrate(durationMs: Long, amplitude: Int = 180) {
        scope.launch {
            try {
                val isHapticsEnabled = userPrefs.hapticFeedbackEnabledFlow.first()
                if (!isHapticsEnabled) return@launch

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(VibrationEffect.createOneShot(durationMs, amplitude.coerceIn(1, 255)))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator?.vibrate(durationMs)
                }
            } catch (e: Exception) {
                // Ignore vibration failure
            }
        }
    }

    companion object {
        @Volatile
        private var instance: SoundEffectsManager? = null

        fun getInstance(context: Context): SoundEffectsManager {
            return instance ?: synchronized(this) {
                instance ?: SoundEffectsManager(context.applicationContext).also { instance = it }
            }
        }

        private const val SAMPLE_RATE = 44100

        private fun generateChirp(startFreq: Float, endFreq: Float, durationMs: Int): ByteArray {
            val numSamples = (SAMPLE_RATE * (durationMs / 1000f)).toInt()
            val samples = ShortArray(numSamples)
            val bytes = ByteArray(numSamples * 2)

            for (i in 0 until numSamples) {
                val progress = i.toFloat() / numSamples
                val currentFreq = startFreq + (endFreq - startFreq) * progress
                val time = i.toDouble() / SAMPLE_RATE
                // Smooth envelope (fast attack, natural exponential decay)
                val envelope = if (progress < 0.1f) {
                    progress / 0.1f
                } else {
                    exp(-3.5 * (progress - 0.1f)).toFloat()
                }
                val sampleVal = (sin(2.0 * PI * currentFreq * time) * envelope * 24000).toInt()
                samples[i] = sampleVal.coerceIn(-32768, 32767).toShort()
            }

            var byteIdx = 0
            for (s in samples) {
                bytes[byteIdx++] = (s.toInt() and 0xFF).toByte()
                bytes[byteIdx++] = ((s.toInt() shr 8) and 0xFF).toByte()
            }
            return bytes
        }

        private fun generateDoubleChime(freq1: Float, freq2: Float, durationMs: Int): ByteArray {
            val numSamples = (SAMPLE_RATE * (durationMs / 1000f)).toInt()
            val samples = ShortArray(numSamples)
            val bytes = ByteArray(numSamples * 2)
            val midSample = numSamples / 2

            for (i in 0 until numSamples) {
                val isSecondTone = i >= midSample
                val currentFreq = if (isSecondTone) freq2 else freq1
                val noteProgress = if (isSecondTone) {
                    (i - midSample).toFloat() / (numSamples - midSample)
                } else {
                    i.toFloat() / midSample
                }
                val time = i.toDouble() / SAMPLE_RATE

                val envelope = if (noteProgress < 0.08f) {
                    noteProgress / 0.08f
                } else {
                    exp(-4.0 * (noteProgress - 0.08f)).toFloat()
                }
                val sampleVal = (sin(2.0 * PI * currentFreq * time) * envelope * 22000).toInt()
                samples[i] = sampleVal.coerceIn(-32768, 32767).toShort()
            }

            var byteIdx = 0
            for (s in samples) {
                bytes[byteIdx++] = (s.toInt() and 0xFF).toByte()
                bytes[byteIdx++] = ((s.toInt() shr 8) and 0xFF).toByte()
            }
            return bytes
        }

        private fun generateDescendPop(startFreq: Float, endFreq: Float, durationMs: Int): ByteArray {
            val numSamples = (SAMPLE_RATE * (durationMs / 1000f)).toInt()
            val samples = ShortArray(numSamples)
            val bytes = ByteArray(numSamples * 2)

            for (i in 0 until numSamples) {
                val progress = i.toFloat() / numSamples
                val currentFreq = startFreq - (startFreq - endFreq) * progress
                val time = i.toDouble() / SAMPLE_RATE
                val envelope = exp(-5.0 * progress).toFloat()
                val sampleVal = (sin(2.0 * PI * currentFreq * time) * envelope * 26000).toInt()
                samples[i] = sampleVal.coerceIn(-32768, 32767).toShort()
            }

            var byteIdx = 0
            for (s in samples) {
                bytes[byteIdx++] = (s.toInt() and 0xFF).toByte()
                bytes[byteIdx++] = ((s.toInt() shr 8) and 0xFF).toByte()
            }
            return bytes
        }

        private fun generateCrystalPing(freq: Float, durationMs: Int): ByteArray {
            val numSamples = (SAMPLE_RATE * (durationMs / 1000f)).toInt()
            val samples = ShortArray(numSamples)
            val bytes = ByteArray(numSamples * 2)

            for (i in 0 until numSamples) {
                val progress = i.toFloat() / numSamples
                val time = i.toDouble() / SAMPLE_RATE
                val envelope = exp(-4.5 * progress).toFloat()
                // Mix fundamental and octave harmonic for metallic crystal ping
                val tone = 0.7 * sin(2.0 * PI * freq * time) + 0.3 * sin(2.0 * PI * (freq * 2) * time)
                val sampleVal = (tone * envelope * 25000).toInt()
                samples[i] = sampleVal.coerceIn(-32768, 32767).toShort()
            }

            var byteIdx = 0
            for (s in samples) {
                bytes[byteIdx++] = (s.toInt() and 0xFF).toByte()
                bytes[byteIdx++] = ((s.toInt() shr 8) and 0xFF).toByte()
            }
            return bytes
        }

        private fun generateTick(freq: Float, durationMs: Int): ByteArray {
            val numSamples = (SAMPLE_RATE * (durationMs / 1000f)).toInt()
            val samples = ShortArray(numSamples)
            val bytes = ByteArray(numSamples * 2)

            for (i in 0 until numSamples) {
                val progress = i.toFloat() / numSamples
                val time = i.toDouble() / SAMPLE_RATE
                val envelope = exp(-10.0 * progress).toFloat()
                val sampleVal = (sin(2.0 * PI * freq * time) * envelope * 18000).toInt()
                samples[i] = sampleVal.coerceIn(-32768, 32767).toShort()
            }

            var byteIdx = 0
            for (s in samples) {
                bytes[byteIdx++] = (s.toInt() and 0xFF).toByte()
                bytes[byteIdx++] = ((s.toInt() shr 8) and 0xFF).toByte()
            }
            return bytes
        }
    }
}
