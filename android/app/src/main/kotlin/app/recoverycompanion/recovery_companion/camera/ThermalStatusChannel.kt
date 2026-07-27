package app.recoverycompanion.recovery_companion.camera

import android.content.Context
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart's `ThermalStatusChannel`
 * (lib/platform/camera/thermal_status_channel.dart) to
 * `PowerManager.getCurrentThermalStatus()` / `addThermalStatusListener`
 * (API 29+), per DESIGN.md §4.3 — the guardrail that degrades the live call
 * to audio-only when the device is overheating instead of letting the OS
 * throttle or kill the app unpredictably.
 *
 * Below API 29, both the method call and the event stream report/emit
 * nothing meaningful ("-1", mapped to `ThermalStatus.unknown` on the Dart
 * side) rather than attempting a guardrail the OS doesn't support there.
 */
class ThermalStatusChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "app.recoverycompanion.recovery_companion/thermal_status"
        const val EVENT_CHANNEL = "app.recoverycompanion.recovery_companion/thermal_status_events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    private var listener: PowerManager.OnThermalStatusChangedListener? = null

    fun start() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    fun stop() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        removeListener()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getCurrentThermalStatus" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    result.success(powerManager?.currentThermalStatus ?: -1)
                } else {
                    result.success(-1)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && powerManager != null) {
            val newListener = PowerManager.OnThermalStatusChangedListener { status ->
                events.success(status)
            }
            listener = newListener
            powerManager.addThermalStatusListener(newListener)
        }
    }

    override fun onCancel(arguments: Any?) {
        removeListener()
    }

    private fun removeListener() {
        val current = listener ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            powerManager?.removeThermalStatusListener(current)
        }
        listener = null
    }
}
