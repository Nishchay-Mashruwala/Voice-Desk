package com.rajvee.mobile

import android.app.Application
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Starts the app's Flutter engine with the process instead of with the window,
 * so a recording keeps going when the window closes (Back, swiped away from
 * Recents): the recording notification's service keeps the process alive, and
 * with it the engine that records. MainActivity shows this engine.
 */
class VoiceDeskApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        // Free storage where recordings are kept (lib/engine/audio/free_space.dart).
        MethodChannel(engine.dartExecutor.binaryMessenger, "voicedesk/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "freeBytes" -> {
                    val path = call.arguments as? String
                    if (path == null) result.error("bad_args", "path expected", null)
                    else result.success(StatFs(path).availableBytes)
                }
                else -> result.notImplemented()
            }
        }
        // How hot the phone is (lib/engine/pipeline/conditions.dart): processing slows down or waits.
        MethodChannel(engine.dartExecutor.binaryMessenger, "voicedesk/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "thermalStatus" -> result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                        (getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus
                    else 0
                )
                else -> result.notImplemented()
            }
        }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "main"
    }
}
