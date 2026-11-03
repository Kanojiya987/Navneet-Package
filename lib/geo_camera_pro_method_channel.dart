import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'geo_camera_pro_platform_interface.dart';
import 'src/models/location_data.dart';

/// An implementation of [GeoCameraProPlatform] that uses method channels.
class MethodChannelGeoCameraPro extends GeoCameraProPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('geo_camera_pro');
  final EventChannel _eventChannel = const EventChannel(
    'geo_camera_pro/location_events',
  );

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<int> getPhysicalOrientationDegrees() async {
    try {
      final degrees = await methodChannel.invokeMethod<int>(
        'getPhysicalOrientationDegrees',
      );
      return degrees ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> startTracking({
    required int intervalMilliseconds,
    required int distanceFilterMeters,
  }) async {
    await methodChannel.invokeMethod<void>('startTracking', <String, Object>{
      'intervalMilliseconds': intervalMilliseconds,
      'distanceFilterMeters': distanceFilterMeters,
    });
  }

  @override
  Future<void> stopTracking() async {
    await methodChannel.invokeMethod<void>('stopTracking');
  }

  @override
  Future<bool> get isTracking async =>
      await methodChannel.invokeMethod<bool>('isTracking') ?? false;

  @override
  Stream<LocationData> get locationUpdates =>
      _eventChannel.receiveBroadcastStream().map((dynamic event) {
        if (event is! Map<Object?, Object?>) {
          throw const FormatException('Invalid native location event.');
        }
        if (event['type'] == 'error') {
          throw PlatformException(
            code: event['code'] as String? ?? 'location_error',
            message: event['message'] as String?,
          );
        }
        return LocationData.fromMap(event);
      });
}
