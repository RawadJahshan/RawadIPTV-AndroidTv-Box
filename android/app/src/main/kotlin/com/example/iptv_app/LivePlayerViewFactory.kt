@file:OptIn(androidx.media3.common.util.UnstableApi::class)

package com.example.iptv_app

import android.content.Context
import android.util.Log
import android.view.View
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Factory registered with Flutter as `rawad_iptv/live_player_view`.
 *
 * Each [create] call produces a [LivePlayerPlatformView] that hosts an
 * Android [PlayerView] (SurfaceView-backed) and attaches it to the current
 * ExoPlayer instance held by [LivePlayerManager].
 */
class LivePlayerViewFactory(
    private val playerManager: LivePlayerManager,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return LivePlayerPlatformView(context, viewId, playerManager)
    }
}

/**
 * Thin wrapper around [PlayerView] exposed as a Flutter PlatformView.
 *
 * The manager enforces that only one [PlayerView] is attached to the player at
 * a time, which prevents duplicate native surfaces during fullscreen toggles.
 */
class LivePlayerPlatformView(
    context: Context,
    private val viewId: Int,
    private val playerManager: LivePlayerManager,
) : PlatformView {

    companion object {
        private const val TAG = "LivePlayerView"
    }

    private val playerView: PlayerView = PlayerView(context).apply {
        useController = false                                    // Flutter owns all controls/overlays
        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)        // Flutter renders the spinner
        keepScreenOn = true
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT      // BoxFit.contain equivalent
        isFocusable = false
        isFocusableInTouchMode = false
    }

    init {
        playerManager.attachPlayerView(playerView)
        Log.d(TAG, "[$viewId] created, player attached=${playerView.player != null}")
    }

    override fun getView(): View = playerView

    override fun dispose() {
        Log.d(TAG, "[$viewId] disposed")
        playerManager.detachPlayerView(playerView)
    }
}
