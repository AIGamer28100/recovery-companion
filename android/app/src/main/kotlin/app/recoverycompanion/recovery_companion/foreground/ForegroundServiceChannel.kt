package app.recoverycompanion.recovery_companion.foreground

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart's `ForegroundServiceChannel`
 * (lib/platform/foreground_service/foreground_service_channel.dart) to
 * [CallForegroundService]'s start/stop lifecycle, per DESIGN.md §3.9.
 */
class ForegroundServiceChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "app.recoverycompanion.recovery_companion/foreground_service"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    fun start() {
        channel.setMethodCallHandler(this)
    }

    fun stop() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val intent = Intent(context, CallForegroundService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                result.success(null)
            }
            "stop" -> {
                val intent = Intent(context, CallForegroundService::class.java).apply {
                    action = CallForegroundService.ACTION_END_CALL
                }
                context.startService(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
