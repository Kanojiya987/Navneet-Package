import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../exceptions/geo_camera_exception.dart';
import '../models/geo_camera_config.dart';
import '../models/location_data.dart';
import '../../geo_camera_pro_platform_interface.dart';

/// Coordinates permissions, native background tracking, and cached GPS fixes.
class LocationManager {
  LocationManager(this.config, {GeoCameraProPlatform? platform})
    : _platform = platform ?? GeoCameraProPlatform.instance;

  final GeoCameraConfig config;
  final GeoCameraProPlatform _platform;
  final StreamController<LocationData> _updates =
      StreamController<LocationData>.broadcast();

  StreamSubscription<LocationData>? _nativeSubscription;
  Future<void>? _startOperation;
  LocationData? _latestLocation;
  bool _isTracking = false;
  bool _disposed = false;

  Stream<LocationData> get updates => _updates.stream;
  LocationData? get latestLocation => _latestLocation;
  bool get isTracking => _isTracking;

  /// Reads the native service state and reconnects to its event stream.
  Future<bool> restoreTrackingStatus() async {
    _ensureNotDisposed();
    _listenForUpdates();
    try {
      _isTracking = await _platform.isTracking;
    } on PlatformException catch (error) {
      throw _translatePlatformException(error);
    }
    return _isTracking;
  }

  /// Requests the foreground permission and starts native background updates.
  Future<void> startTracking() {
    _ensureNotDisposed();
    if (_isTracking) return Future<void>.value();
    return _startOperation ??= _startTracking().whenComplete(() {
      _startOperation = null;
    });
  }

  Future<void> _startTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailableException(
        'Location services are disabled on this device.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionException(
        'Location permission is denied. Grant location access in system settings.',
      );
    }
    _ensureNotDisposed();

    _listenForUpdates();

    try {
      if (await restoreTrackingStatus()) return;
      await _platform.startTracking(
        intervalMilliseconds: config.locationInterval.inMilliseconds,
        distanceFilterMeters: config.locationDistanceFilter,
      );
      _isTracking = true;
    } on GeoCameraException {
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
      rethrow;
    } on PlatformException catch (error) {
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
      throw _translatePlatformException(error);
    }
  }

  /// Stops native tracking while preserving the most recent fix in memory.
  Future<void> stopTracking() async {
    final pendingStart = _startOperation;
    if (pendingStart != null) await pendingStart;
    try {
      await _platform.stopTracking();
    } on PlatformException catch (error) {
      throw _translatePlatformException(error);
    } finally {
      _isTracking = false;
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
    }
  }

  /// Returns a fresh acceptable fix, waiting only when the cache is stale.
  Future<LocationData?> locationForCapture() async {
    _ensureNotDisposed();
    final cached = _latestLocation;
    if (cached != null && _isAcceptable(cached)) return cached;

    if (!_isTracking) return null;

    try {
      return await updates
          .firstWhere(_isAcceptable)
          .timeout(config.locationTimeout);
    } on TimeoutException {
      throw const LocationTimeoutException();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await _startOperation;
      if (_isTracking) await stopTracking();
    } finally {
      _isTracking = false;
      _disposed = true;
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
      await _updates.close();
    }
  }

  bool _isAcceptable(LocationData location) {
    final age = DateTime.now().toUtc().difference(location.timestamp.toUtc());
    return !age.isNegative &&
        age <= config.maxLocationAge &&
        location.accuracy <= config.maxLocationAccuracy;
  }

  void _handleLocation(LocationData location) {
    _latestLocation = location;
    _updates.add(location);
  }

  void _listenForUpdates() {
    _nativeSubscription ??= _platform.locationUpdates.listen(
      _handleLocation,
      onError: _handleNativeError,
    );
  }

  void _handleNativeError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _isTracking = false;
    unawaited(_nativeSubscription?.cancel());
    _nativeSubscription = null;
    if (error is PlatformException) {
      _updates.addError(_translatePlatformException(error), stackTrace);
    } else {
      _updates.addError(error, stackTrace);
    }
    unawaited(_stopNativeTrackingAfterError());
  }

  Future<void> _stopNativeTrackingAfterError() async {
    try {
      await _platform.stopTracking();
    } on PlatformException catch (error) {
      if (!_disposed) {
        _updates.addError(
          _translatePlatformException(error),
          StackTrace.current,
        );
      }
    } catch (error, stackTrace) {
      if (!_disposed) _updates.addError(error, stackTrace);
    }
  }

  GeoCameraException _translatePlatformException(PlatformException error) {
    switch (error.code) {
      case 'location_permission_denied':
      case 'permission_denied':
        return LocationPermissionException(
          error.message ?? 'Location permission denied.',
        );
      case 'location_unavailable':
      case 'location_services_disabled':
        return LocationUnavailableException(
          error.message ?? 'Location services are unavailable.',
        );
      default:
        return GeoCameraException(
          error.message ?? 'Native location tracking failed.',
          code: error.code,
          details: error.details,
        );
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('LocationManager has been disposed.');
    }
  }
}
