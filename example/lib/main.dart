import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geo_camera_pro/geo_camera_pro.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.geoCamera});

  final GeoCameraPro? geoCamera;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GeoCameraPro _geoCamera;
  StreamSubscription<LocationData>? _locationSubscription;
  StreamSubscription<GeoCameraException>? _errorSubscription;
  CaptureResult? _capture;
  LocationData? _location;
  String? _errorMessage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _geoCamera = widget.geoCamera ?? GeoCameraPro();
    _locationSubscription = _geoCamera.locationUpdates.listen((location) {
      if (mounted) setState(() => _location = location);
    }, onError: (Object error) => _showError(error));
    _errorSubscription = _geoCamera.errors.listen(_showError);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _geoCamera.initialize();
      if (mounted) setState(() => _errorMessage = null);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _startTracking() => _run(_geoCamera.startTracking);

  Future<void> _stopTracking() => _run(_geoCamera.stopTracking);

  Future<void> _switchCamera() => _run(_geoCamera.switchCamera);

  Future<void> _capturePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _geoCamera.capture();
      if (mounted) {
        setState(() {
          _capture = result;
          _errorMessage = null;
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _errorMessage = null);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _errorMessage = error.toString());
  }

  @override
  void dispose() {
    unawaited(_locationSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_disposeCamera());
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    try {
      await _geoCamera.dispose();
    } catch (error) {
      debugPrint('GeoCameraPro dispose failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geo Camera Pro',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('Geo Camera Pro')),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: _geoCamera,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _buildPreview(),
                const SizedBox(height: 12),
                _buildCameraActions(),
                const SizedBox(height: 16),
                _buildTrackingControls(),
                const SizedBox(height: 12),
                _buildLocationCard(),
                if (_errorMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _buildErrorCard(_errorMessage!),
                ],
                if (_capture != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _buildCaptureCard(_capture!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _geoCamera.cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        height: 260,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Camera preview unavailable. Check camera permission.',
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildCameraActions() {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            onPressed: !_busy && _geoCamera.isInitialized
                ? _capturePhoto
                : null,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Capture Photo'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Switch front/rear camera',
          onPressed: !_busy && _geoCamera.isInitialized ? _switchCamera : null,
          icon: const Icon(Icons.flip_camera_android),
        ),
      ],
    );
  }

  Widget _buildTrackingControls() {
    return ValueListenableBuilder<bool>(
      valueListenable: _geoCamera.trackingStatus,
      builder: (context, tracking, _) => Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: !_busy && !tracking ? _startTracking : null,
              child: const Text('Start Tracking'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: !_busy && tracking ? _stopTracking : null,
              child: const Text('Stop Tracking'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    final location = _location ?? _geoCamera.latestLocation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _geoCamera.isTracking
                  ? 'GPS tracking active'
                  : 'GPS tracking stopped',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              location == null
                  ? 'Waiting for a GPS fix'
                  : 'Latitude: ${location.latitude}\n'
                        'Longitude: ${location.longitude}\n'
                        'Accuracy: ${location.accuracy.toStringAsFixed(1)} m\n'
                        'GPS fix: ${location.timestamp.toLocal()}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureCard(CaptureResult result) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Image.file(
            File(result.imagePath),
            height: 300,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Could not preview saved image: $error'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              'Saved: ${result.imagePath}\n'
              'Captured: ${result.timestamp.toLocal()}\n'
              'Original dimensions: '
              '${result.originalWidth ?? "unknown"} × '
              '${result.originalHeight ?? "unknown"}\n'
              'Final dimensions: ${result.width ?? "unknown"} × '
              '${result.height ?? "unknown"}\n'
              'Portrait crop applied: ${result.portraitCropApplied ? "yes" : "no"}\n'
              'GPS status: ${result.gpsStatus.name}'
              '${result.gpsError == null ? "" : " (${result.gpsError})"}\n'
              'GPS: ${result.latitude ?? "unavailable"}, '
              '${result.longitude ?? "unavailable"}\n'
              'Accuracy: ${result.accuracy?.toStringAsFixed(1) ?? "unavailable"} m',
            ),
          ),
        ],
      ),
    );
  }
}
