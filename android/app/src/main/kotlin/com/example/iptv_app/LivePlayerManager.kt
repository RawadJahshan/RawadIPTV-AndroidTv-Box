@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package com.example.iptv_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Manages a singleton ExoPlayer instance for Live TV playback.
 *
 * Commands arrive via [MethodChannel] (initialize / play / stop / release).
 * State events are pushed to Flutter via [EventChannel].
 *
 * The player survives PlatformView recreation (e.g. fullscreen toggle) because
 * the view only holds a reference obtained through [getPlayer] and reattaches
 * via [addViewListener].
 */
class LivePlayerManager(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "LivePlayerManager"
    }

    /* ------------------------------------------------------------------ */
    /*  Public surface                                                     */
    /* ------------------------------------------------------------------ */

    /** Currently-active ExoPlayer, or null before [initialize]/after [release]. */
    fun getPlayer(): ExoPlayer? = player

    /** Register a callback that fires when the player instance is (re)created. */
    fun addViewListener(listener: () -> Unit) { viewListeners.add(listener) }

    /** Remove a previously-registered view listener. */
    fun removeViewListener(listener: () -> Unit) { viewListeners.remove(listener) }

    /** [EventChannel.StreamHandler] that Flutter subscribes to. */
    val eventStreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            Log.d(TAG, "EventChannel: Flutter subscribed")
        }
        override fun onCancel(arguments: Any?) {
            eventSink = null
            Log.d(TAG, "EventChannel: Flutter unsubscribed")
        }
    }

    /* ------------------------------------------------------------------ */
    /*  MethodChannel dispatch                                             */
    /* ------------------------------------------------------------------ */

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                initialize()
                result.success(null)
            }
            "play" -> {
                val url = call.argument<String>("url") ?: ""
                @Suppress("UNCHECKED_CAST")
                val headers =
                    (call.argument<Map<String, String>>("headers") ?: emptyMap())
                play(url, headers)
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /* ------------------------------------------------------------------ */
    /*  Internal state                                                     */
    /* ------------------------------------------------------------------ */

    private var player: ExoPlayer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isFirstFrame = false
    private val viewListeners = mutableListOf<() -> Unit>()

    /**
     * Shared [DefaultHttpDataSource.Factory] whose default request properties
     * are updated before each [play] call so ExoPlayer's auto-detected
     * [DefaultMediaSourceFactory] picks them up.
     */
    private val httpDataSourceFactory = DefaultHttpDataSource.Factory()
        .setConnectTimeoutMs(10_000)
        .setReadTimeoutMs(10_000)
        .setAllowCrossProtocolRedirects(true)

    /** Periodic heartbeat so Flutter's watchdog can detect stalled playback. */
    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            player?.let { p ->
                if (p.isPlaying) {
                    sendEvent(mapOf(
                        "event" to "heartbeat",
                        "position" to p.currentPosition,
                    ))
                }
            }
            mainHandler.postDelayed(this, 10_000)
        }
    }

    /* ------------------------------------------------------------------ */
    /*  Player lifecycle                                                   */
    /* ------------------------------------------------------------------ */

    private fun initialize() {
        Log.d(TAG, "initialize: creating ExoPlayer")
        release()                       // tear down any previous instance

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs        = */ 2_000,
                /* maxBufferMs        = */ 30_000,
                /* bufferForPlayback  = */ 500,
                /* bufferForRebuffer  = */ 1_000,
            )
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()

        val mediaSourceFactory = DefaultMediaSourceFactory(httpDataSourceFactory)

        player = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setHandleAudioBecomingNoisy(true)
            .build()
            .apply {
                playWhenReady = true
                repeatMode = Player.REPEAT_MODE_OFF
                addListener(playerListener)
            }

        // Notify platform views so they attach the new player surface.
        viewListeners.forEach { it() }

        // Start heartbeat.
        mainHandler.removeCallbacks(heartbeatRunnable)
        mainHandler.postDelayed(heartbeatRunnable, 10_000)

        sendEvent(mapOf("event" to "initialized"))
        Log.d(TAG, "initialize: done")
    }

    private fun play(url: String, headers: Map<String, String>) {
        val p = player
        if (p == null) {
            Log.w(TAG, "play: player not initialized, ignoring")
            return
        }

        isFirstFrame = false
        Log.d(TAG, "play: $url")

        // Update headers before creating the media source.
        httpDataSourceFactory.setDefaultRequestProperties(headers)

        val mediaItem = MediaItem.fromUri(url)

        // Stop current playback cleanly, then load the new item.
        p.stop()
        p.clearMediaItems()
        p.setMediaItem(mediaItem)
        p.prepare()
        // playWhenReady is already true from initialization.

        sendEvent(mapOf("event" to "mediaSet", "url" to url))
    }

    private fun stop() {
        Log.d(TAG, "stop")
        player?.stop()
        player?.clearMediaItems()
        isFirstFrame = false
    }

    private fun release() {
        Log.d(TAG, "release")
        mainHandler.removeCallbacks(heartbeatRunnable)
        player?.removeListener(playerListener)
        player?.release()
        player = null
        isFirstFrame = false
        sendEvent(mapOf("event" to "released"))
    }

    /* ------------------------------------------------------------------ */
    /*  ExoPlayer listener                                                 */
    /* ------------------------------------------------------------------ */

    private val playerListener = object : Player.Listener {

        override fun onPlaybackStateChanged(state: Int) {
            val name = when (state) {
                Player.STATE_IDLE      -> "idle"
                Player.STATE_BUFFERING -> "buffering"
                Player.STATE_READY     -> "ready"
                Player.STATE_ENDED     -> "ended"
                else                   -> "unknown"
            }
            Log.d(TAG, "playbackState: $name")
            sendEvent(mapOf("event" to "playbackState", "state" to name))

            when (state) {
                Player.STATE_BUFFERING ->
                    sendEvent(mapOf("event" to "buffering", "value" to true))
                Player.STATE_READY ->
                    sendEvent(mapOf("event" to "buffering", "value" to false))
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            Log.d(TAG, "isPlaying: $isPlaying")
            sendEvent(mapOf("event" to "playing", "value" to isPlaying))
        }

        override fun onVideoSizeChanged(videoSize: VideoSize) {
            if (videoSize.width > 0 && videoSize.height > 0) {
                Log.d(TAG, "videoSize: ${videoSize.width}x${videoSize.height}")
                sendEvent(mapOf(
                    "event"  to "videoSize",
                    "width"  to videoSize.width,
                    "height" to videoSize.height,
                ))
            }
        }

        override fun onRenderedFirstFrame() {
            Log.d(TAG, "onRenderedFirstFrame")
            if (!isFirstFrame) {
                isFirstFrame = true
                sendEvent(mapOf("event" to "firstFrame"))
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            Log.e(TAG, "playerError: ${error.errorCodeName} – ${error.message}")
            sendEvent(mapOf(
                "event"   to "error",
                "code"    to error.errorCode,
                "message" to (error.message ?: "Unknown playback error"),
            ))
        }

        override fun onTracksChanged(tracks: Tracks) {
            for (group in tracks.groups) {
                if (group.type == C.TRACK_TYPE_VIDEO) {
                    for (i in 0 until group.length) {
                        val format = group.getTrackFormat(i)
                        if (format.frameRate > 0) {
                            Log.d(TAG, "fps: ${format.frameRate}")
                            sendEvent(mapOf(
                                "event" to "fps",
                                "value" to format.frameRate.toDouble(),
                            ))
                            return
                        }
                    }
                }
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  Helpers                                                            */
    /* ------------------------------------------------------------------ */

    private fun sendEvent(data: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(data) }
    }
}
