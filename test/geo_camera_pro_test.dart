import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_camera_pro/geo_camera_pro.dart';
import 'package:geo_camera_pro/geo_camera_pro_platform_interface.dart';
import 'package:geo_camera_pro/geo_camera_pro_method_channel.dart';
import 'package:geo_camera_pro/src/location/location_manager.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockGeoCameraProPlatform
    with MockPlatformInterfaceMixin
    implements GeoCameraProPlatform {
  int stopTrackingCalls = 0;
  bool nativeTracking = false;
  final StreamController<LocationData> locationEvents =
      StreamController<LocationData>.broadcast();

  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<int> getPhysicalOrientationDegrees() async => 0;

  @override
  Future<void> startTracking({
    required int intervalMilliseconds,
    required int distanceFilterMeters,
  }) async {}

  @override
  Future<void> stopTracking() async {
    stopTrackingCalls += 1;
    nativeTracking = false;
  }

  @override
  Future<bool> get isTracking async => nativeTracking;

  @override
  Stream<LocationData> get locationUpdates => locationEvents.stream;
}

void main() {
  final GeoCameraProPlatform initialPlatform = GeoCameraProPlatform.instance;

  test('$MethodChannelGeoCameraPro is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelGeoCameraPro>());
  });

  test('getPlatformVersion', () async {
    GeoCameraPro geoCameraProPlugin = GeoCameraPro();
    MockGeoCameraProPlatform fakePlatform = MockGeoCameraProPlatform();
    GeoCameraProPlatform.instance = fakePlatform;

    expect(await geoCameraProPlugin.getPlatformVersion(), '42');
  });

  test('location and capture models expose GPS timestamps', () {
    final location = LocationData.fromMap(<String, Object>{
      'latitude': 45.5,
      'longitude': -73.6,
      'accuracy': 4.2,
      'timestamp': 1_800_000_000_000,
    });
    final capture = CaptureResult(
      imagePath: r'C:\photos\capture.jpg',
      timestamp: DateTime.utc(2026, 11, 1),
      location: location,
    );

    expect(capture.latitude, 45.5);
    expect(capture.longitude, -73.6);
    expect(capture.accuracy, 4.2);
    expect(capture.locationTimestamp, location.timestamp);
    expect(capture.toJson()['locationTimestamp'], isA<String>());
  });

  test('capture without a fix exposes its GPS error and status', () {
    final capture = CaptureResult(
      imagePath: r'C:\photos\capture.jpg',
      timestamp: DateTime.utc(2026, 11, 1),
      gpsError: 'Location timed out.',
      originalWidth: 800,
      originalHeight: 600,
      width: 450,
      height: 600,
      portraitCropApplied: true,
    );

    expect(capture.gpsStatus, CaptureGpsStatus.unavailable);
    expect(capture.toJson()['gpsError'], 'Location timed out.');
    expect(capture.toJson()['width'], 450);
    expect(capture.toJson()['portraitCropApplied'], isTrue);
  });

  test(
    'stopTracking reaches native even after local tracking status is false',
    () async {
      final platform = MockGeoCameraProPlatform();
      final manager = LocationManager(
        const GeoCameraConfig(),
        platform: platform,
      );

      await manager.stopTracking();

      expect(platform.stopTrackingCalls, 1);
      await manager.dispose();
      await platform.locationEvents.close();
    },
  );

  test('native location stream errors stop the native tracker', () async {
    final platform = MockGeoCameraProPlatform()..nativeTracking = true;
    final manager = LocationManager(
      const GeoCameraConfig(),
      platform: platform,
    );
    expect(await manager.restoreTrackingStatus(), isTrue);
    final errorExpectation = expectLater(
      manager.updates,
      emitsError(isA<LocationUnavailableException>()),
    );

    platform.locationEvents.addError(
      PlatformException(code: 'location_unavailable'),
    );

    await errorExpectation;
    await Future<void>.delayed(Duration.zero);
    expect(platform.stopTrackingCalls, 1);
    expect(manager.isTracking, isFalse);
    await manager.dispose();
    await platform.locationEvents.close();
  });

  test('uses a cached fix only when both age and accuracy pass', () async {
    final platform = MockGeoCameraProPlatform()..nativeTracking = true;
    final manager = LocationManager(
      const GeoCameraConfig(
        maxLocationAge: Duration(seconds: 10),
        maxLocationAccuracy: 5,
      ),
      platform: platform,
    );
    await manager.restoreTrackingStatus();
    final location = LocationData(
      latitude: 10,
      longitude: 20,
      accuracy: 3,
      timestamp: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    platform.locationEvents.add(location);
    await Future<void>.delayed(Duration.zero);

    expect(await manager.locationForCapture(), same(location));
    await manager.dispose();
    await platform.locationEvents.close();
  });

  test('rejects stale and inaccurate cached fixes', () async {
    for (final location in <LocationData>[
      LocationData(
        latitude: 10,
        longitude: 20,
        accuracy: 1,
        timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      ),
      LocationData(
        latitude: 10,
        longitude: 20,
        accuracy: 20,
        timestamp: DateTime.now().toUtc(),
      ),
    ]) {
      final platform = MockGeoCameraProPlatform()..nativeTracking = true;
      final manager = LocationManager(
        const GeoCameraConfig(
          maxLocationAge: Duration(seconds: 10),
          maxLocationAccuracy: 5,
          locationTimeout: Duration.zero,
        ),
        platform: platform,
      );
      await manager.restoreTrackingStatus();
      platform.locationEvents.add(location);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        manager.locationForCapture(),
        throwsA(isA<LocationTimeoutException>()),
      );

      await manager.dispose();
      await platform.locationEvents.close();
    }
  });
}
