package com.example.iptv_app

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_INFO_CHANNEL = "rawad_iptv/device_info"
        private const val IS_ANDROID_TV_METHOD = "isAndroidTv"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    IS_ANDROID_TV_METHOD -> result.success(isAndroidTvDevice())
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAndroidTvDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isTelevisionMode =
            uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION

        val hasLeanbackFeature = packageManager.hasSystemFeature("android.software.leanback")

        return isTelevisionMode || hasLeanbackFeature
    }
}
