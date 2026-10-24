package mm.lab.lab_commission

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Detects calls ringing the lab so Dart can log the ones from a delivery
/// man's number. One ring session is tracked here: Android first sends
/// RINGING without the number and again with it, so the number is kept until
/// the call ends, then one event (`number`, `at`, `answered`) is emitted.
///
/// shortcut: the receiver lives on this activity, so calls are only seen while
/// the app process is alive (backgrounded is fine, force-stopped is not).
/// Upgrade to a manifest-declared receiver that starts the app if calls are
/// ever missed when the app is closed.
class MainActivity : FlutterActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var receiverRegistered = false

    private var ringNumber: String? = null
    private var ringAt = 0L
    private var ringAnswered = false

    private val phoneStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != TelephonyManager.ACTION_PHONE_STATE_CHANGED) return
            val number = intent.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            when (intent.getStringExtra(TelephonyManager.EXTRA_STATE)) {
                TelephonyManager.EXTRA_STATE_RINGING -> {
                    if (ringAt == 0L) {
                        ringAt = System.currentTimeMillis()
                        ringAnswered = false
                        ringNumber = null
                    }
                    if (!number.isNullOrEmpty()) ringNumber = number
                }
                TelephonyManager.EXTRA_STATE_OFFHOOK -> if (ringAt != 0L) ringAnswered = true
                TelephonyManager.EXTRA_STATE_IDLE -> endRing()
            }
        }
    }

    private fun endRing() {
        val number = ringNumber
        val at = ringAt
        val sink = eventSink
        if (at != 0L && !number.isNullOrEmpty() && sink != null) {
            val payload = mapOf(
                "number" to number,
                "at" to at,
                "answered" to ringAnswered
            )
            runOnUiThread { sink.success(payload) }
        }
        ringNumber = null
        ringAt = 0L
        ringAnswered = false
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    if (!receiverRegistered) {
                        registerReceiver(
                            phoneStateReceiver,
                            IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
                        )
                        receiverRegistered = true
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    if (receiverRegistered) {
                        unregisterReceiver(phoneStateReceiver)
                        receiverRegistered = false
                    }
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "has" -> result.success(hasCallPermissions())
                    "request" -> requestCallPermissions(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasCallPermissions() = listOf(
        Manifest.permission.READ_PHONE_STATE,
        Manifest.permission.READ_CALL_LOG
    ).all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestCallPermissions(result: MethodChannel.Result) {
        val missing = listOf(
            Manifest.permission.READ_PHONE_STATE,
            Manifest.permission.READ_CALL_LOG
        ).filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_CALL_LOG)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == REQUEST_CALL_LOG) {
            pendingPermission?.success(hasCallPermissions())
            pendingPermission = null
        } else {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    companion object {
        private const val EVENT_CHANNEL = "lab.calls/events"
        private const val METHOD_CHANNEL = "lab.calls/permissions"
        private const val REQUEST_CALL_LOG = 41
    }
}
