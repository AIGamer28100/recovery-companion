package app.recoverycompanion.recovery_companion.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.audiofx.AcousticEchoCanceler
import android.util.Log

/**
 * Wraps `android.media.AudioTrack` in MODE_STREAM for gapless, flushable
 * 24kHz PCM16 playback of the model's voice, per DESIGN.md §3.3/§3.4.
 *
 * Why not a container-based Dart player: this needs to start playing before
 * all the data exists and be flushable mid-buffer on barge-in with no
 * audible click — `AudioTrack.pause()` + `flush()` gives that precisely;
 * wrapping raw PCM into per-chunk WAV headers for a generic player does not.
 */
class PlaybackEngine(private val context: Context) {
    companion object {
        private const val TAG = "PlaybackEngine"
        private const val SAMPLE_RATE_HZ = 24000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_OUT_MONO
        private const val ENCODING = AudioFormat.ENCODING_PCM_16BIT

        // A deliberate small multiple over the platform minimum for jitter
        // tolerance, per DESIGN.md §3.6 ("2-3 chunks / 120-200ms"). This is a
        // starting point to validate against real round-trip numbers on a
        // device, not a final answer.
        private const val BUFFER_SIZE_MULTIPLIER = 3
    }

    private var audioTrack: AudioTrack? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var audioManager: AudioManager? = null
    private var previousAudioMode: Int? = null

    /**
     * Creates the AudioTrack, puts AudioManager into MODE_IN_COMMUNICATION
     * (required on many devices for the AEC/NS pairing described in §3.4 to
     * actually engage), and checks (but does not need to bind, since this
     * side owns playback, not the capture session) whether hardware
     * AcousticEchoCanceler support exists on this device.
     *
     * Returns whether hardware echo cancellation is available, so the Dart
     * side can surface the "tap to interrupt" fallback affordance when it
     * isn't (§3.4).
     */
    fun init(): Boolean {
        release()

        val minBufferSize = AudioTrack.getMinBufferSize(SAMPLE_RATE_HZ, CHANNEL_CONFIG, ENCODING)
        val bufferSize = if (minBufferSize > 0) {
            minBufferSize * BUFFER_SIZE_MULTIPLIER
        } else {
            SAMPLE_RATE_HZ * BUFFER_SIZE_MULTIPLIER // ~1s/3 fallback, shouldn't happen
        }

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        val format = AudioFormat.Builder()
            .setSampleRate(SAMPLE_RATE_HZ)
            .setChannelMask(CHANNEL_CONFIG)
            .setEncoding(ENCODING)
            .build()

        val track = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        audioTrack = track
        track.play()

        val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = manager
        previousAudioMode = manager.mode
        manager.mode = AudioManager.MODE_IN_COMMUNICATION

        val aecAvailable = AcousticEchoCanceler.isAvailable()
        if (aecAvailable) {
            // Bound to this AudioTrack's session mainly so the platform is
            // aware an AEC-capable playback+capture pairing is in play on
            // this stream; the actual echo-cancellation processing happens
            // on the CAPTURE side (see `MicCapture`'s `echoCancel: true`,
            // which enables `record`'s own AcousticEchoCanceler bound to its
            // AudioRecord session — the session this side doesn't have
            // direct access to). This instance is created defensively and
            // released immediately; what we actually need from here is the
            // availability boolean.
            try {
                val canceler = AcousticEchoCanceler.create(track.audioSessionId)
                canceler?.enabled = true
                echoCanceler = canceler
            } catch (e: Exception) {
                Log.w(TAG, "AcousticEchoCanceler.create failed despite isAvailable()==true", e)
            }
        } else {
            Log.w(TAG, "AcousticEchoCanceler.isAvailable() == false on this device")
        }

        return aecAvailable
    }

    fun write(pcm16: ByteArray) {
        audioTrack?.write(pcm16, 0, pcm16.size)
    }

    fun pause() {
        val track = audioTrack ?: return
        if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
            track.pause()
        }
    }

    /** The barge-in primitive: pause, drop every buffered sample. */
    fun flush() {
        val track = audioTrack ?: return
        pause()
        track.flush()
    }

    fun play() {
        val track = audioTrack ?: return
        if (track.playState != AudioTrack.PLAYSTATE_PLAYING) {
            track.play()
        }
    }

    fun setVolume(volume: Float) {
        audioTrack?.setVolume(volume.coerceIn(0f, 1f))
    }

    /** Cumulative buffer-underrun count, for diagnostic reporting (§3.6). */
    fun underrunCount(): Int = audioTrack?.underrunCount ?: 0

    /** Tears down the AudioTrack/AEC and restores the previous audio mode. */
    fun release() {
        echoCanceler?.release()
        echoCanceler = null

        audioTrack?.let { track ->
            try {
                if (track.playState == AudioTrack.PLAYSTATE_PLAYING) track.stop()
            } catch (e: IllegalStateException) {
                Log.w(TAG, "AudioTrack.stop() failed during release", e)
            }
            track.release()
        }
        audioTrack = null

        audioManager?.let { manager ->
            manager.mode = previousAudioMode ?: AudioManager.MODE_NORMAL
        }
        audioManager = null
        previousAudioMode = null
    }
}
