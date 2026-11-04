package com.navidev.geo_camera_pro

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.OrientationEventListener

/** GeoCameraProPlugin */
class GeoCameraProPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var orientationEventListener: OrientationEventListener? = null

    @Volatile
    private var lastPhysicalOrientationDegrees: Int = 0

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "geo_camera_pro")
        channel.setMethodCallHandler(this)
        eventChannel =
            EventChannel(flutterPluginBinding.binaryMessenger, "geo_camera_pro/location_events")
        eventChannel.setStreamHandler(this)

        orientationEventListener = object : android.view.OrientationEventListener(context) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == android.view.OrientationEventListener.ORIENTATION_UNKNOWN) return
                lastPhysicalOrientationDegrees = if (orientation in 45..134) {
                    90   // Landscape Left
                } else if (orientation in 135..224) {
                    180  // Portrait Down
                } else if (orientation in 225..314) {
                    270  // Landscape Right
                } else {
                    0    // Portrait Up
                }
            }
        }
        if (orientationEventListener?.canDetectOrientation() == true) {
            orientationEventListener?.enable()
        }
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        when (call.method) {
            "getPlatformVersion" -> result.success("Android ${Build.VERSION.RELEASE}")
            "getPhysicalOrientationDegrees" -> result.success(lastPhysicalOrientationDegrees)
            "startTracking" -> startTracking(call, result)
            "stopTracking" -> {
                context.stopService(Intent(context, LocationTrackingService::class.java))
                result.success(null)
            }
            "isTracking" -> result.success(LocationTrackingService.isRunning)
            else -> result.notImplemented()
        }
    }

    private fun startTracking(call: MethodCall, result: Result) {
        val hasFine =
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val hasCoarse =
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        if (!hasFine && !hasCoarse) {
            result.error(
                "location_permission_denied",
                "Grant location permission before starting tracking.",
                null,
            )
            return
        }

        val intent = Intent(context, LocationTrackingService::class.java)
            .setAction(LocationTrackingService.ACTION_START)
            .putExtra(
                LocationTrackingService.EXTRA_INTERVAL,
                call.argument<Number>("intervalMilliseconds")?.toLong() ?: 5000L,
            )
            .putExtra(
                LocationTrackingService.EXTRA_DISTANCE,
                call.argument<Number>("distanceFilterMeters")?.toFloat() ?: 0f,
            )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            result.success(null)
        } catch (error: SecurityException) {
            result.error("location_permission_denied", error.message, null)
        } catch (error: IllegalStateException) {
            result.error("location_service_start_failed", error.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        val preferences = context.getSharedPreferences(
            LocationTrackingService.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val latitude = preferences.getString(LocationTrackingService.KEY_LATITUDE, null)
            ?.toDoubleOrNull()
        val longitude = preferences.getString(LocationTrackingService.KEY_LONGITUDE, null)
            ?.toDoubleOrNull()
        val accuracy = preferences.getString(LocationTrackingService.KEY_ACCURACY, null)
            ?.toDoubleOrNull()
        if (latitude != null && longitude != null && accuracy != null) {
            events.success(
                mapOf(
                    "type" to "location",
                    "latitude" to latitude,
                    "longitude" to longitude,
                    "accuracy" to accuracy,
                    "timestamp" to preferences.getLong(
                        LocationTrackingService.KEY_TIMESTAMP,
                        0L,
                    ),
                ),
            )
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        orientationEventListener?.disable()
        orientationEventListener = null
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
    }

    companion object {
        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        fun sendLocation(location: android.location.Location) {
            if (!location.hasAccuracy()) return
            eventSink?.success(
                mapOf(
                    "type" to "location",
                    "latitude" to location.latitude,
                    "longitude" to location.longitude,
                    "accuracy" to location.accuracy.toDouble(),
                    "timestamp" to location.time,
                ),
            )
        }

        fun sendError(code: String, message: String) {
            eventSink?.error(code, message, null)
        }
    }
}
