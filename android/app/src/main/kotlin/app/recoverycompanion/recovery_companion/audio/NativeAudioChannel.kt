package app.recoverycompanion.recovery_companion.audio

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

/**
 * Bridges Dart's `NativeAudioChannel` (lib/platform/audio/native_audio_channel.dart)
 * to [PlaybackEngine]. This is the only Kotlin class that talks to Flutter
 * for playback/echo-cancellation — everything else in `audio/` is plain
 * Android audio code with no Flutter dependency, per DESIGN.md §3.3/§3.4.
 */
class NativeAudioChannel(context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "app.recoverycompanion.recovery_companion/native_audio"
        const val EVENT_CHANNEL = "app.recoverycompanion.recovery_companion/native_audio_events"
    }

    private val engine = PlaybackEngine(context)

    // Flutter dispatches MethodChannel calls on the main/UI thread by
    // default. `write`/`flush`/`pause` do blocking AudioTrack I/O — on the
    // main thread that's a real stutter risk for the breathing-orb animation
    // under real-time audio load, not just a theoretical concern. A
    // background TaskQueue moves this handler off the UI thread entirely.
    private val taskQueue = messenger.makeBackgroundTaskQueue()
    private val methodChannel =
        MethodChannel(messenger, METHOD_CHANNEL, StandardMethodCodec.INSTANCE, taskQueue)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private var eventSink: EventChannel.EventSink? = null
    private var lastUnderrunCount = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    fun start() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun stop() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        engine.release()
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                lastUnderrunCount = 0
                val aecAvailable = engine.init()
                result.success(aecAvailable)
            }
            "write" -> {
                val bytes = call.arguments as? ByteArray
                if (bytes == null) {
                    result.error("bad_args", "write expects a ByteArray", null)
                    return
                }
                engine.write(bytes)
                maybeReportUnderrun()
                result.success(null)
            }
            "pause" -> {
                engine.pause()
                result.success(null)
            }
            "flush" -> {
                engine.flush()
                result.success(null)
            }
            "play" -> {
                engine.play()
                result.success(null)
            }
            "setVolume" -> {
                val volume = (call.arguments as? Double)?.toFloat()
                if (volume == null) {
                    result.error("bad_args", "setVolume expects a double", null)
                    return
                }
                engine.setVolume(volume)
                result.success(null)
            }
            "release" -> {
                engine.release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Diagnostic-only underrun signal (§3.6: buffer sizing needs real-device
     * validation). `AudioTrack.getUnderrunCount()` requires API 24+; below
     * that this is silently a no-op.
     *
     * Runs on the background task queue thread (see `methodChannel` above),
     * but `EventSink.success()` is `@UiThread`-only in Flutter's engine —
     * must hop back to the main thread before calling it.
     */
    private fun maybeReportUnderrun() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val count = engine.underrunCount()
        if (count > lastUnderrunCount) {
            lastUnderrunCount = count
            mainHandler.post { eventSink?.success(mapOf("type" to "underrun")) }
        }
    }
}
