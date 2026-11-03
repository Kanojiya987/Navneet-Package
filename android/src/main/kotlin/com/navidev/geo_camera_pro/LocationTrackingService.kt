package com.navidev.geo_camera_pro

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.Looper

class LocationTrackingService : Service() {
    private lateinit var locationManager: LocationManager
    private var locationListener: LocationListener? = null
    private val preferences by lazy {
        getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    }

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopTracking()
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_START ||
            (intent == null && preferences.getBoolean(KEY_TRACKING, false))
        ) {
            val interval = intent?.getLongExtra(
                EXTRA_INTERVAL,
                preferences.getLong(KEY_INTERVAL, DEFAULT_INTERVAL),
            ) ?: preferences.getLong(KEY_INTERVAL, DEFAULT_INTERVAL)
            val distance = intent?.getFloatExtra(
                EXTRA_DISTANCE,
                preferences.getFloat(KEY_DISTANCE, 0f),
            ) ?: preferences.getFloat(KEY_DISTANCE, 0f)
            preferences.edit()
                .putLong(KEY_INTERVAL, interval)
                .putFloat(KEY_DISTANCE, distance)
                .apply()

            val notification = createNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            beginTracking(interval, distance)
        }
        return START_STICKY
    }

    private fun beginTracking(interval: Long, distance: Float) {
        if (!hasLocationPermission()) {
            reportFailure("location_permission_denied", "Location permission was revoked.")
            preferences.edit().putBoolean(KEY_TRACKING, false).apply()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        stopTracking()
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                publishLocation(location)
            }

            @Deprecated("Deprecated in Android")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) {
                val locationProviderEnabled = locationManager.getProviders(true).any {
                    it == LocationManager.GPS_PROVIDER ||
                        it == LocationManager.NETWORK_PROVIDER
                }
                if (!locationProviderEnabled) {
                    reportFailure(
                        "location_unavailable",
                        "All location providers are disabled.",
                    )
                    stopSelf()
                }
            }
        }
        locationListener = listener

        try {
            val providers = locationManager.getProviders(true).filter {
                it == LocationManager.GPS_PROVIDER ||
                    it == LocationManager.NETWORK_PROVIDER
            }
            if (providers.isEmpty()) {
                reportFailure("location_unavailable", "No location provider is enabled.")
                preferences.edit().putBoolean(KEY_TRACKING, false).apply()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return
            }
            providers.forEach { provider ->
                locationManager.requestLocationUpdates(
                    provider,
                    interval.coerceAtLeast(1000L),
                    distance.coerceAtLeast(0f),
                    listener,
                    Looper.getMainLooper(),
                )
                locationManager.getLastKnownLocation(provider)?.let { lastKnown ->
                    publishLocation(lastKnown)
                }
            }
            isRunning = true
            preferences.edit().putBoolean(KEY_TRACKING, true).apply()
        } catch (error: SecurityException) {
            reportFailure("location_permission_denied", error.message ?: "Permission denied.")
            preferences.edit().putBoolean(KEY_TRACKING, false).apply()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } catch (error: IllegalArgumentException) {
            reportFailure("location_unavailable", error.message ?: "No location provider.")
            preferences.edit().putBoolean(KEY_TRACKING, false).apply()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fineGranted =
            checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        val coarseGranted =
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED
        return fineGranted || coarseGranted
    }

    private fun stopTracking() {
        locationListener?.let { listener ->
            locationManager.removeUpdates(listener)
            locationListener = null
        }
        isRunning = false
        preferences.edit().putBoolean(KEY_TRACKING, false).apply()
    }

    private fun reportFailure(code: String, message: String) {
        GeoCameraProPlugin.sendError(code, message)
    }

    private fun publishLocation(location: Location) {
        if (!location.hasAccuracy()) return
        preferences.edit()
            .putString(KEY_LATITUDE, location.latitude.toString())
            .putString(KEY_LONGITUDE, location.longitude.toString())
            .putString(KEY_ACCURACY, location.accuracy.toString())
            .putLong(KEY_TIMESTAMP, location.time)
            .apply()
        GeoCameraProPlugin.sendLocation(location)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Location tracking",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while GeoCameraPro records location updates."
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Location tracking active")
            .setContentText("GeoCameraPro is recording GPS updates.")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        stopTracking()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.navidev.geo_camera_pro.START_TRACKING"
        const val ACTION_STOP = "com.navidev.geo_camera_pro.STOP_TRACKING"
        const val EXTRA_INTERVAL = "intervalMilliseconds"
        const val EXTRA_DISTANCE = "distanceFilterMeters"
        const val DEFAULT_INTERVAL = 5000L

        private const val NOTIFICATION_CHANNEL_ID = "geo_camera_pro_location"
        private const val NOTIFICATION_ID = 8701
        const val PREFERENCES_NAME = "geo_camera_pro_tracking"
        const val KEY_TRACKING = "tracking"
        const val KEY_INTERVAL = "interval"
        const val KEY_DISTANCE = "distance"
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_ACCURACY = "accuracy"
        const val KEY_TIMESTAMP = "timestamp"

        @Volatile
        var isRunning: Boolean = false
            private set
    }
}
