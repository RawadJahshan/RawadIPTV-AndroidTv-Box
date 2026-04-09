package com.example.iptv_app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_INFO_CHANNEL = "rawad_iptv/device_info"
        private const val IS_ANDROID_TV_METHOD = "isAndroidTv"

        private const val LIVE_PLAYER_METHOD_CHANNEL = "rawad_iptv/live_player"
        private const val LIVE_PLAYER_EVENT_CHANNEL  = "rawad_iptv/live_player/events"
        private const val LIVE_PLAYER_VIEW_TYPE      = "rawad_iptv/live_player_view"
    }

    private lateinit var livePlayerManager: LivePlayerManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // --- Device info channel (existing) ---
        MethodChannel(messenger, DEVICE_INFO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    IS_ANDROID_TV_METHOD -> result.success(isAndroidTvDevice())
                    else -> result.notImplemented()
                }
            }

        // --- Live TV player channels (new) ---
        livePlayerManager = LivePlayerManager(this)

        MethodChannel(messenger, LIVE_PLAYER_METHOD_CHANNEL)
            .setMethodCallHandler(livePlayerManager)

        EventChannel(messenger, LIVE_PLAYER_EVENT_CHANNEL)
            .setStreamHandler(livePlayerManager.eventStreamHandler)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                LIVE_PLAYER_VIEW_TYPE,
                LivePlayerViewFactory(livePlayerManager),
            )
    }

    private fun isAndroidTvDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isTelevisionMode =
            uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION

        val hasLeanbackFeature = packageManager.hasSystemFeature("android.software.leanback")

        return isTelevisionMode || hasLeanbackFeature
    }
}
