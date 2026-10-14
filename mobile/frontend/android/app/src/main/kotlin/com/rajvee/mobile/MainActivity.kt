package com.rajvee.mobile

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // The engine outlives this window (VoiceDeskApplication), so closing the
    // window doesn't stop a recording.
    override fun getCachedEngineId(): String = VoiceDeskApplication.ENGINE_ID
}
