# geo_camera_pro

A Flutter plugin for portrait-normalized camera captures with GPS metadata and
native background location tracking on Android and iOS.

> Background location behavior depends on platform permissions, device power
> management, and operating-system policy. This package has not been validated
> on physical Android and iOS devices in every supported OS configuration.

## Installation

```yaml
dependencies:
  geo_camera_pro: ^0.0.1
```

Run `flutter pub get`, then complete the platform permission setup below.

## Platform setup

### Android

The plugin contributes the location permissions, location foreground-service
permissions, and non-exported tracking service through manifest merging. The
host application must also declare camera access if it does not already receive
that permission through its camera implementation:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

The service is started while the app is visible and runs as a location
foreground service with an ongoing notification. Android 10+ restricts
background location access. Starting tracking from the foreground avoids the
background-start restriction; apps that need to initiate location work while
already in the background must request `ACCESS_BACKGROUND_LOCATION` according
to the Android version's staged permission flow. Android 14+ requires the
location foreground-service type and
`FOREGROUND_SERVICE_LOCATION`; the plugin declares these for manifest merging.
The host app should request notification permission on Android 13+ if it needs
the ongoing notification to appear in the notification drawer.

Users can revoke permissions or disable location at any time. Android may stop
the service under system or manufacturer power-management policies. Force-stop
terminates the service; tracking is not promised to continue or restart after a
force-stop.

### iOS

Add these keys to the host app's `ios/Runner/Info.plist` (customize the text for
your app):

```xml
<key>NSCameraUsageDescription</key>
<string>Capture photos.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Attach location to captured photos.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Continue location tracking while tracking is active.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
</array>
```

Enable the Location updates background capability for the Runner target in
Xcode. The plugin requests Always authorization when starting background
tracking and reports an error if it is not granted. iOS controls scheduling and
may suspend or terminate apps; tracking is not guaranteed after the user
force-quits the app. Validate permission prompts and background behavior on a
physical iPhone. If `enableAudio` is set, also add
`NSMicrophoneUsageDescription` and handle microphone permission in the host app.

## Usage

```dart
import 'package:camera/camera.dart';
import 'package:geo_camera_pro/geo_camera_pro.dart';

final geoCamera = GeoCameraPro(
  config: const GeoCameraConfig(
    maxLocationAge: Duration(seconds: 20),
    maxLocationAccuracy: 30,
    portraitCropMode: PortraitCropMode.centerCrop,
    embedLocationInExif: true,
  ),
);

await geoCamera.initialize();
await geoCamera.startTracking();

final result = await geoCamera.capture();
print(result.imagePath);
print(result.latitude);
print(result.longitude);
print(result.accuracy);
print(result.timestamp); // Capture/shutter request timestamp.
print(result.locationTimestamp); // Original GPS fix timestamp.

await geoCamera.stopTracking();
await geoCamera.dispose();
```

Use the camera controller for a live preview:

```dart
final controller = geoCamera.cameraController;
if (controller != null && controller.value.isInitialized) {
  final preview = CameraPreview(controller);
}
```

The `camera` package is a dependency of this plugin and must be imported by
applications that use `CameraPreview`.

Listen for fixes and asynchronous errors:

```dart
final locationSubscription = geoCamera.locationUpdates.listen((location) {
  print('${location.latitude}, ${location.longitude}');
  print('accuracy: ${location.accuracy} m');
  print('fix time: ${location.timestamp}');
});

final errorSubscription = geoCamera.errors.listen((error) {
  print(error);
});
```

Cancel subscriptions and dispose the controller when no longer needed. The
controller disposes the camera when the app is inactive and reinitializes it
when the app resumes; native location tracking is not stopped by that camera
lifecycle transition.

## Configuration and capture behavior

`GeoCameraConfig` supports:

- Camera resolution preset and optional audio.
- A custom output directory. By default, images are saved under the app's
  documents directory in `geo_camera_pro/`.
- Portrait output ratio (default 3:4) and JPEG quality.
- `maxLocationAge`, `maxLocationAccuracy`, `locationTimeout`,
  `locationInterval`, and `locationDistanceFilter`.
- Optional GPS EXIF embedding and a JSON sidecar (enabled by default).

Capture uses a cached GPS fix when it meets the configured age and accuracy.
Otherwise it waits up to `locationTimeout` for an acceptable update. If that
wait times out, the photo is still saved without a location and a
`LocationTimeoutException` is emitted on `errors`. The result and sidecar then
contain `null` GPS fields. If tracking is stopped and there is no fresh cached
fix, capture also continues without GPS and emits a
`LocationUnavailableException`. Camera, permission, and file-processing
failures are thrown as typed `GeoCameraException` subclasses.

The capture timestamp is recorded immediately before the camera plugin's
`takePicture` shutter request; the camera plugin does not expose a hardware
shutter timestamp. The GPS timestamp is the original timestamp reported by the
native location provider. When GPS is unavailable, `CaptureResult.gpsStatus`
and `CaptureResult.gpsError` describe the failure while the photo is still
saved. Android uses the configured location interval as a minimum update
cadence; iOS scheduling remains controlled by Core Location.

## Portrait processing

The processor applies EXIF orientation exactly once to the decoded pixels,
then removes the orientation tag before saving JPEG. With the default
`PortraitCropMode.centerCrop`, landscape images retain their full height and
are cropped symmetrically from the sides to the configured width-to-height
ratio (default 3:4); the scene is never rotated merely to make it portrait.
Already-portrait images retain their full dimensions and aspect ratio.
`PortraitCropMode.preservePortrait` instead crops a landscape image only enough
to make it portrait. Both modes produce portrait pixel dimensions without
stretching. The saved JPEG is reopened and checked for portrait dimensions.
Processing runs in a worker isolate. Corrupted or unsupported images fail with
`ImageProcessingException`.

## Background tracking limitations

- Tracking starts only after the user grants location access and the platform
  allows the foreground/background execution mode.
- Android keeps a foreground service notification visible while tracking.
  Android force-stop and vendor power-management controls can terminate it.
- iOS Always access and the Location updates background capability are
  required. iOS may still throttle or stop background work.
- Neither platform guarantees tracking after force-stop/force-quit.
- Test permission upgrade flows, notification visibility, battery behavior, and
  GPS accuracy on real devices; emulators are not representative of all
  background restrictions.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Camera initialization fails | Grant camera access and add `NSCameraUsageDescription` on iOS. |
| Location permission error | Grant location access in system settings; iOS background tracking needs Always. |
| iOS background-mode error | Add `UIBackgroundModes` with `location` and enable Location updates in Xcode. |
| No GPS fix | Enable device location, check the permission precision, and allow time for a fix. |
| No Android notification | Check Android 13+ notification permission and notification-channel settings. |
| Image is too tightly cropped | Use a wider `portraitAspectRatio` or select `PortraitCropMode.preservePortrait`. |
| Build fails after manifest changes | Clean the host app build and verify merged permissions/service in the Android manifest. |

## Development

Run `flutter analyze` and `flutter test` from the plugin directory. Android can
be compiled from the example app with `flutter build apk --debug`. iOS builds
require macOS with Xcode; this project environment is Windows.
#   N a v n e e t - P a c k a g e  
 