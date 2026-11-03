import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'geo_camera_pro_method_channel.dart';
import 'src/models/location_data.dart';

abstract class GeoCameraProPlatform extends PlatformInterface {
  /// Constructs a GeoCameraProPlatform.
  GeoCameraProPlatform() : super(token: _token);

  static final Object _token = Object();

  static GeoCameraProPlatform _instance = MethodChannelGeoCameraPro();

  /// The default instance of [GeoCameraProPlatform] to use.
  ///
  /// Defaults to [MethodChannelGeoCameraPro].
  static GeoCameraProPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [GeoCameraProPlatform] when
  /// they register themselves.
  static set instance(GeoCameraProPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Returns physical hardware orientation in degrees (0, 90, 180, 270).
  Future<int> getPhysicalOrientationDegrees() async => 0;

  /// Starts the native background location service.
  Future<void> startTracking({
    required int intervalMilliseconds,
    required int distanceFilterMeters,
  }) {
    throw UnimplementedError('startTracking() has not been implemented.');
  }

  /// Stops the native background location service.
  Future<void> stopTracking() {
    throw UnimplementedError('stopTracking() has not been implemented.');
  }

  /// Whether native background tracking is active.
  Future<bool> get isTracking async =>
      throw UnimplementedError('isTracking has not been implemented.');

  /// GPS fixes and status errors emitted by native tracking.
  Stream<LocationData> get locationUpdates =>
      throw UnimplementedError('locationUpdates has not been implemented.');
}
