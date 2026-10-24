package com.recharge.recall_next

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.UUID

class MainActivity : FlutterActivity() {
    private var incomingShareChannel: MethodChannel? = null
    private val incomingShares = ArrayDeque<Map<String, Any>>()
    private var launchShareHandled = false
    private var overflowReported = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Do not re-import the launch Intent after activity/process recreation.
        // Unreviewed source text is intentionally not written into saved state.
        launchShareHandled = savedInstanceState?.getBoolean(SHARE_HANDLED) ?: false
        if (!launchShareHandled) receiveShare(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingShareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "recall/incoming_share"
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        val share = incomingShares.pollFirst()
                        if (incomingShares.isEmpty()) overflowReported = false
                        result.success(share)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Android otherwise retains the original launch Intent in getIntent().
        setIntent(intent)
        receiveShare(intent)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(SHARE_HANDLED, launchShareHandled)
        super.onSaveInstanceState(outState)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        incomingShareChannel?.setMethodCallHandler(null)
        incomingShareChannel = null
        incomingShares.clear()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun receiveShare(intent: Intent?) {
        val incoming = intent ?: return
        if (incoming.action != Intent.ACTION_SEND &&
            incoming.action != Intent.ACTION_SEND_MULTIPLE) return
        launchShareHandled = true
        val payload = parseShare(incoming)
        if (incomingShares.size < MAX_PENDING_SHARES) {
            incomingShares.addLast(payload)
        } else if (!overflowReported) {
            overflowReported = true
            incomingShares.addLast(issue("queueFull"))
        }
        // A notification carries no source content. Dart explicitly takes each
        // queued payload once, avoiding a launch/live-delivery duplication race.
        incomingShareChannel?.invokeMethod("onShareAvailable", null)
    }

    private fun parseShare(intent: Intent): Map<String, Any> {
        try {
            if (intent.action != Intent.ACTION_SEND || intent.type != "text/plain") {
                return issue("unsupported")
            }
            // Never dereference attachments or request/persist URI permission.
            if (intent.hasExtra(Intent.EXTRA_STREAM) || intent.data != null) {
                return issue("unsupported")
            }
            val clips = intent.clipData
            if (clips != null) {
                for (index in 0 until clips.itemCount) {
                    if (clips.getItemAt(index).uri != null) return issue("unsupported")
                }
            }
            val source = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
                ?: (if (clips?.itemCount == 1) clips.getItemAt(0).text else null)
                ?: return issue("empty")
            // UTF-16 length is a cheap bound before allocating an encoded copy.
            if (source.length > MAX_TEXT_BYTES) return issue("tooLarge")
            val text = source.toString()
            if (text.toByteArray(Charsets.UTF_8).size > MAX_TEXT_BYTES) return issue("tooLarge")
            if (text.isBlank()) return issue("empty")
            return mapOf("id" to UUID.randomUUID().toString(), "status" to "text", "text" to text)
        } catch (_: RuntimeException) {
            // Malformed extras are untrusted. Do not log exceptions/source text.
            return issue("invalidPayload")
        }
    }

    private fun issue(status: String): Map<String, Any> =
        mapOf("id" to UUID.randomUUID().toString(), "status" to status)

    companion object {
        private const val MAX_TEXT_BYTES = 1024 * 1024
        private const val MAX_PENDING_SHARES = 4
        private const val SHARE_HANDLED = "recall.incomingShareHandled"
    }
}
