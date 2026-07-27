package app.recoverycompanion.recovery_companion

import app.recoverycompanion.recovery_companion.audio.NativeAudioChannel
import app.recoverycompanion.recovery_companion.camera.ThermalStatusChannel
import app.recoverycompanion.recovery_companion.foreground.ForegroundServiceChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Registers the app's own platform channels (audio playback/echo-cancellation,
 * the call foreground service, and the camera thermal guardrail —
 * DESIGN.md §3.3/§3.4/§3.9/§4.3) alongside the plugin-registered ones
 * Flutter wires up automatically.
 */
class MainActivity : FlutterActivity() {
    private var nativeAudioChannel: NativeAudioChannel? = null
    private var foregroundServiceChannel: ForegroundServiceChannel? = null
    private var thermalStatusChannel: ThermalStatusChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        nativeAudioChannel = NativeAudioChannel(applicationContext, messenger).also { it.start() }
        foregroundServiceChannel =
            ForegroundServiceChannel(applicationContext, messenger).also { it.start() }
        thermalStatusChannel =
            ThermalStatusChannel(applicationContext, messenger).also { it.start() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nativeAudioChannel?.stop()
        nativeAudioChannel = null
        foregroundServiceChannel?.stop()
        foregroundServiceChannel = null
        thermalStatusChannel?.stop()
        thermalStatusChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
