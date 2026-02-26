package com.example.ppgsamsungwearosapp

import android.os.Handler
import android.os.Looper
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.NodeClient
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {
    private lateinit var messageClient: MessageClient
    private lateinit var nodeClient: NodeClient

    private val handler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    private var watchConnected: Boolean? = null
    private var watchNames: List<String> = emptyList()
    private var lastPpgTimestamp: Long? = null
    private var latestPayload: String = ""
    private var latestPayloadPreview: String = ""

    private val statusUpdater = object : Runnable {
        override fun run() {
            refreshConnectedNodes()
            sendStatusUpdate()
            handler.postDelayed(this, STATUS_REFRESH_INTERVAL_MS)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        messageClient = Wearable.getMessageClient(this)
        nodeClient = Wearable.getNodeClient(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                        startListening()
                    }

                    override fun onCancel(arguments: Any?) {
                        stopListening()
                        eventSink = null
                    }
                },
            )
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != MESSAGE_PATH) {
            return
        }
        val payload = String(messageEvent.data, StandardCharsets.UTF_8)
        val preview = if (payload.length > MAX_PAYLOAD_PREVIEW) {
            payload.takeLast(MAX_PAYLOAD_PREVIEW)
        } else {
            payload
        }

        handler.post {
            lastPpgTimestamp = System.currentTimeMillis()
            latestPayload = payload
            latestPayloadPreview = preview
            sendStatusUpdate()
        }
    }

    private fun startListening() {
        messageClient.addListener(this)
        refreshConnectedNodes()
        handler.post(statusUpdater)
    }

    private fun stopListening() {
        messageClient.removeListener(this)
        handler.removeCallbacks(statusUpdater)
    }

    private fun refreshConnectedNodes() {
        nodeClient.connectedNodes
            .addOnSuccessListener { nodes -> updateConnectedNodes(nodes) }
            .addOnFailureListener {
                watchConnected = null
                watchNames = emptyList()
                sendStatusUpdate()
            }
    }

    private fun updateConnectedNodes(nodes: List<Node>) {
        if (nodes.isEmpty()) {
            watchConnected = false
            watchNames = emptyList()
        } else {
            watchConnected = true
            watchNames = nodes.map { it.displayName }
        }
        sendStatusUpdate()
    }

    private fun sendStatusUpdate() {
        val now = System.currentTimeMillis()
        val sharing = lastPpgTimestamp?.let { now - it <= PPG_SHARING_TIMEOUT_MS } == true
        val payload = mapOf(
            "watchConnected" to watchConnected,
            "watchNames" to watchNames,
            "ppgSharing" to sharing,
            "lastPpgTimestamp" to lastPpgTimestamp,
            "payloadPreview" to latestPayloadPreview,
            "payload" to latestPayload,
        )
        eventSink?.success(payload)
    }

    companion object {
        private const val CHANNEL_NAME = "ppg_events"
        private const val MESSAGE_PATH = "/ppg-data"
        private const val MAX_PAYLOAD_PREVIEW = 500
        private const val PPG_SHARING_TIMEOUT_MS = 5_000L
        private const val STATUS_REFRESH_INTERVAL_MS = 1_000L
    }
}
