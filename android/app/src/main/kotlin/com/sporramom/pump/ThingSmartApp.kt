package com.sporramom.pump

import android.app.Application
import android.util.Log
import com.thingclips.smart.home.sdk.ThingHomeSdk

class ThingSmartApp : Application() {
    companion object {
        private const val TAG = "ThingSmartApp"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Initializing Tuya SDK...")

        try {
            ThingHomeSdk.init(this)
            ThingHomeSdk.setDebugMode(false)
            Log.d(TAG, "Tuya SDK initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Exception during SDK initialization: ${e.message}", e)
        }
    }
}

