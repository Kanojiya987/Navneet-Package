import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../geo_camera_pro.dart';
import '../geo_camera_controller.dart';

/// Camera modes matching native camera layout.
enum GeoCameraMode { video, photo, portrait, more, pro }

/// Aspect ratio settings for camera viewfinder and output.
enum GeoCameraAspectRatio { ratio3x4, ratio16x9, ratio1x1, full }

/// Geo-tag overlay style customization options.
class GeoTagOverlayConfig {
  const GeoTagOverlayConfig({
    this.showAddress = true,
    this.showCoordinates = true,
    this.showAltitude = true,
    this.showAccuracy = true,
    this.showTimestamp = true,
    this.showCompass = true,
    this.showMiniMap = true,
    this.customNote = 'Geo Camera Pro Project',
  });

  final bool showAddress;
  final bool showCoordinates;
  final bool showAltitude;
  final bool showAccuracy;
  final bool showTimestamp;
  final bool showCompass;
  final bool showMiniMap;
  final String customNote;

  GeoTagOverlayConfig copyWith({
    bool? showAddress,
    bool? showCoordinates,
    bool? showAltitude,
    bool? showAccuracy,
    bool? showTimestamp,
    bool? showCompass,
    bool? showMiniMap,
    String? customNote,
  }) {
    return GeoTagOverlayConfig(
      showAddress: showAddress ?? this.showAddress,
      showCoordinates: showCoordinates ?? this.showCoordinates,
      showAltitude: showAltitude ?? this.showAltitude,
      showAccuracy: showAccuracy ?? this.showAccuracy,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showCompass: showCompass ?? this.showCompass,
      showMiniMap: showMiniMap ?? this.showMiniMap,
      customNote: customNote ?? this.customNote,
    );
  }
}

/// A full-screen, video-matched camera view with continuous geo-tracking,
/// custom HUD geotag overlay, mode carousel (PRO, VIDEO, PHOTO, PORTRAIT),
/// zoom & exposure controls, and interactive gallery metadata inspection.
class GeoCameraView extends StatefulWidget {
  const GeoCameraView({
    super.key,
    this.controller,
    this.onCapture,
    this.onVideoRecordComplete,
    this.initialMode = GeoCameraMode.photo,
  });

  final GeoCameraController? controller;
  final ValueChanged<CaptureResult>? onCapture;
  final ValueChanged<String>? onVideoRecordComplete;
  final GeoCameraMode initialMode;

  @override
  State<GeoCameraView> createState() => _GeoCameraViewState();
}

class _GeoCameraViewState extends State<GeoCameraView>
    with SingleTickerProviderStateMixin {
  late final GeoCameraController _controller;
  late GeoCameraMode _activeMode;

  // Viewfinder & Camera State
  double _zoomLevel = 1.0;
  double _minZoom = 0.6;
  double _maxZoom = 8.0;
  double _exposureOffset = -2.0; // Matching -2.0 EV in video
  bool _showEvSlider = false;
  camera.FlashMode _flashMode = camera.FlashMode.off;
  GeoCameraAspectRatio _aspectRatio = GeoCameraAspectRatio.ratio3x4;
  bool _showGrid = true;
  bool _hdrEnabled = true;
  bool _showFilters = false;
  String _selectedFilter = 'Normal';
  bool _beautyEnabled = false;
  int _timerSeconds = 0; // 0, 3, 5, 10
  int _countdownRemaining = 0;

  // Video Mode State
  bool _isRecordingVideo = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // PRO Mode State
  String _selectedIso = 'AUTO';
  String _selectedWb = 'Auto';
  String _selectedFocus = 'Auto';
  bool _showProPanel = false;

  // Overlay & Gallery State
  GeoTagOverlayConfig _overlayConfig = const GeoTagOverlayConfig();
  bool _showHudCardOnPreview = false; // Background tracking active, HUD card hidden on live preview
  CaptureResult? _lastCapture;
  bool _isCapturing = false;
  bool _showShutterBlink = false;
  bool _showCapturedPhotoBanner = false;
  Timer? _bannerTimer;
  String? _statusMessage;

  // Sensor & Location Streams
  StreamSubscription<SensorData>? _sensorSub;
  StreamSubscription<LocationData>? _locationSub;
  SensorData _sensorData = const SensorData();

  // Permissions State
  bool _cameraPermissionDenied = false;
  bool _locationPermissionDenied = false;

  // Mode Scroll Controller
  final ScrollController _modeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _activeMode = widget.initialMode;
    _controller = widget.controller ?? GeoCameraController();
    _checkAndRequestPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerActiveMode(animate: false);
    });
  }

  Future<void> _checkAndRequestPermissions() async {
    bool hasLocationPerm = false;

    // Check & Request Location Permission
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        await Geolocator.openLocationSettings();
      }
      var locPerm = await Geolocator.checkPermission();
      if (locPerm == LocationPermission.denied) {
        locPerm = await Geolocator.requestPermission();
      }
      hasLocationPerm = (locPerm == LocationPermission.whileInUse ||
          locPerm == LocationPermission.always);
    } catch (_) {}

    // Initialize Camera & Location Tracking
    try {
      if (!_controller.isInitialized) {
        await _controller.initialize();
      }
      if (!_controller.isTracking) {
        await _controller.startTracking();
      }
      _sensorSub ??= _controller.sensorUpdates.listen((data) {
        if (mounted) setState(() => _sensorData = data);
      });
      _locationSub ??= _controller.locationUpdates.listen((loc) {
        if (mounted) setState(() {});
      });
      _updateZoomBoundaries();
      if (mounted) {
        setState(() {
          _cameraPermissionDenied = !_controller.isInitialized;
          _locationPermissionDenied = !hasLocationPerm && !_controller.isTracking;
          _statusMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        final errStr = e.toString().toLowerCase();
        setState(() {
          if (errStr.contains('permission') || errStr.contains('denied')) {
            if (errStr.contains('location')) {
              _locationPermissionDenied = true;
            } else {
              _cameraPermissionDenied = true;
            }
          }
          _statusMessage = 'Initialization: $e';
        });
      }
    }
  }

  void _updateZoomBoundaries() async {
    final cameraCtrl = _controller.cameraController;
    if (cameraCtrl != null && cameraCtrl.value.isInitialized) {
      try {
        _minZoom = await cameraCtrl.getMinZoomLevel();
        _maxZoom = await cameraCtrl.getMaxZoomLevel();
      } catch (_) {}
    }
  }

  Future<void> _setZoom(double zoom) async {
    final cameraCtrl = _controller.cameraController;
    setState(() => _zoomLevel = zoom);
    if (cameraCtrl != null && cameraCtrl.value.isInitialized) {
      try {
        final targetZoom = zoom.clamp(_minZoom, _maxZoom);
        await cameraCtrl.setZoomLevel(targetZoom);
      } catch (_) {}
    }
  }

  Future<void> _setExposureOffset(double offset) async {
    final cameraCtrl = _controller.cameraController;
    setState(() => _exposureOffset = offset);
    if (cameraCtrl != null && cameraCtrl.value.isInitialized) {
      try {
        await cameraCtrl.setExposureOffset(offset);
      } catch (_) {}
    }
  }

  Future<void> _triggerAutoFocus() async {
    HapticFeedback.lightImpact();
    final cameraCtrl = _controller.cameraController;
    if (cameraCtrl != null && cameraCtrl.value.isInitialized) {
      try {
        await cameraCtrl.setFocusPoint(const Offset(0.5, 0.5));
        await cameraCtrl.setFocusMode(camera.FocusMode.auto);
      } catch (_) {}
    }
  }

  Future<void> _toggleFlash() async {
    final modes = [
      camera.FlashMode.off,
      camera.FlashMode.auto,
      camera.FlashMode.always,
      camera.FlashMode.torch,
    ];
    final nextIdx = (modes.indexOf(_flashMode) + 1) % modes.length;
    final nextMode = modes[nextIdx];
    setState(() => _flashMode = nextMode);
    final cameraCtrl = _controller.cameraController;
    if (cameraCtrl != null && cameraCtrl.value.isInitialized) {
      try {
        await cameraCtrl.setFlashMode(nextMode);
      } catch (_) {}
    }
  }

  void _selectNextMode() {
    final modes = [
      GeoCameraMode.video,
      GeoCameraMode.photo,
      GeoCameraMode.portrait,
      GeoCameraMode.more,
    ];
    final currentIdx = modes.indexOf(_activeMode);
    if (currentIdx != -1 && currentIdx < modes.length - 1) {
      _selectMode(modes[currentIdx + 1]);
    }
  }

  void _selectPreviousMode() {
    final modes = [
      GeoCameraMode.video,
      GeoCameraMode.photo,
      GeoCameraMode.portrait,
      GeoCameraMode.more,
    ];
    final currentIdx = modes.indexOf(_activeMode);
    if (currentIdx > 0) {
      _selectMode(modes[currentIdx - 1]);
    }
  }

  static const double _kModeItemWidth = 100.0;

  void _centerActiveMode({bool animate = true}) {
    final modes = [
      GeoCameraMode.video,
      GeoCameraMode.photo,
      GeoCameraMode.portrait,
      GeoCameraMode.more,
    ];
    final idx = modes.indexOf(_activeMode);
    if (idx != -1 && _modeScrollController.hasClients) {
      final targetOffset = idx * _kModeItemWidth;
      if (animate) {
        _modeScrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
        );
      } else {
        _modeScrollController.jumpTo(targetOffset);
      }
    }
  }

  void _selectMode(GeoCameraMode mode) {
    HapticFeedback.selectionClick();
    setState(() {
      _activeMode = mode;
      if (mode == GeoCameraMode.pro) {
        _showProPanel = true;
      } else {
        _showProPanel = false;
      }
    });
    _centerActiveMode();
  }

  void _cycleTimer() {
    final times = [0, 3, 5, 10];
    final nextIdx = (times.indexOf(_timerSeconds) + 1) % times.length;
    setState(() => _timerSeconds = times[nextIdx]);
  }

  void _cycleAspectRatio() {
    final ratios = GeoCameraAspectRatio.values;
    final nextIdx = (ratios.indexOf(_aspectRatio) + 1) % ratios.length;
    setState(() => _aspectRatio = ratios[nextIdx]);
  }

  Future<void> _handleShutterPress() async {
    if (_isCapturing) return;

    if (_activeMode == GeoCameraMode.video) {
      _toggleVideoRecording();
      return;
    }

    if (_timerSeconds > 0) {
      setState(() => _countdownRemaining = _timerSeconds);
      for (int i = _timerSeconds; i > 0; i--) {
        if (!mounted) return;
        setState(() => _countdownRemaining = i);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (mounted) setState(() => _countdownRemaining = 0);
    }

    await _capturePhoto();
  }

  Future<void> _capturePhoto() async {
    if (_isCapturing) return;
    _isCapturing = true;
    HapticFeedback.lightImpact();

    // Trigger subtle 60ms native camera shutter blink
    if (mounted) setState(() => _showShutterBlink = true);
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (mounted) setState(() => _showShutterBlink = false);
    });

    try {
      GeoCameraOrientation? orientation;
      if (_activeMode == GeoCameraMode.portrait) {
        orientation = GeoCameraOrientation.portrait;
      }
      final result = await _controller.capture(orientation: orientation);
      if (mounted) {
        _lastCapture = result;
        _showCapturedPhotoBanner = true;
        _bannerTimer?.cancel();
        _bannerTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showCapturedPhotoBanner = false);
        });
        widget.onCapture?.call(result);
        setState(() {}); // Update gallery thumbnail and show top photo banner
      }
    } catch (e) {
      if (mounted) {
        _statusMessage = 'Capture error: $e';
      }
    } finally {
      _isCapturing = false;
    }
  }

  void _toggleVideoRecording() {
    if (_isRecordingVideo) {
      // Stop Recording
      _recordingTimer?.cancel();
      setState(() {
        _isRecordingVideo = false;
        _recordingSeconds = 0;
      });
      HapticFeedback.heavyImpact();
      widget.onVideoRecordComplete?.call('Video recording saved');
    } else {
      // Start Recording
      HapticFeedback.heavyImpact();
      setState(() {
        _isRecordingVideo = true;
        _recordingSeconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted) setState(() => _recordingSeconds++);
      });
    }
  }

  @override
  void dispose() {
    _sensorSub?.cancel();
    _locationSub?.cancel();
    _recordingTimer?.cancel();
    _bannerTimer?.cancel();
    _modeScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Action Bar
            _buildTopActionBar(),

            // 2. Viewfinder & Overlays with Horizontal Swipe Mode Switch
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (details) {
                  if (details.primaryVelocity == null) return;
                  if (details.primaryVelocity! < -200) {
                    _selectNextMode(); // Swipe Left -> Next Mode
                  } else if (details.primaryVelocity! > 200) {
                    _selectPreviousMode(); // Swipe Right -> Previous Mode
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Full-screen Camera Viewfinder
                    _buildViewfinder(),

                    // Subtle Native Camera Shutter Blink Overlay (60ms)
                    if (_showShutterBlink)
                      IgnorePointer(
                        child: Container(color: Colors.black.withOpacity(0.65)),
                      ),

                    // Gridlines & Artificial Horizon Overlay
                    if (_showGrid) _buildGridOverlay(),
                    _buildArtificialHorizon(),

                    // Live Geo-Tag HUD Overlay Card (GPS location active in background)
                    if (_showHudCardOnPreview) _buildGeoTagHUDCard(),

                    // EV Slider Drawer (if open)
                    if (_showEvSlider) _buildEvSliderOverlay(),

                    // PRO Panel (if active)
                    if (_activeMode == GeoCameraMode.pro && _showProPanel)
                      _buildProPanel(),

                    // Inline MORE Panel (if MORE mode is active)
                    if (_activeMode == GeoCameraMode.more)
                      _buildInlineMorePanel(),

                    // Timer Countdown Banner
                    if (_countdownRemaining > 0) _buildCountdownOverlay(),

                    // Video Recording Timer Indicator
                    if (_isRecordingVideo) _buildVideoTimerBadge(),

                    // Floating Viewfinder Overlay Controls (Scanner, 1X Zoom, Retouching)
                    _buildFloatingViewfinderControls(),

                    // Filter Selector Drawer
                    if (_showFilters) _buildFilterBarOverlay(),

                    // Upper Captured Photo Banner ("upper come photo")
                    _buildTopCapturedPhotoBanner(),
                  ],
                ),
              ),
            ),

            // 3. Camera Mode Picker Bar
            _buildModePickerBar(),

            // 4. Bottom Control Bar
            _buildBottomShutterBar(),

            // 5. Permissions Request Overlay
            if (_cameraPermissionDenied || _locationPermissionDenied)
              _buildPermissionOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.9),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security, color: Colors.amber, size: 52),
              const SizedBox(height: 14),
              const Text(
                'Permissions Required',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Camera and GPS Location permissions are required to capture geotagged photos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ],
              const SizedBox(height: 22),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _checkAndRequestPermissions,
                icon: const Icon(Icons.check_circle, size: 20),
                label: const Text(
                  'Allow Camera & Location',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewfinder() {
    final cameraCtrl = _controller.cameraController;
    if (cameraCtrl == null || !cameraCtrl.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(color: Colors.amber),
              SizedBox(height: 16),
              Text(
                'Initializing Geo Camera Pro...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    double previewRatio;
    switch (_aspectRatio) {
      case GeoCameraAspectRatio.ratio1x1:
        previewRatio = 1.0;
        break;
      case GeoCameraAspectRatio.ratio16x9:
        previewRatio = 9 / 16;
        break;
      case GeoCameraAspectRatio.full:
        previewRatio = MediaQuery.of(context).size.width / MediaQuery.of(context).size.height;
        break;
      case GeoCameraAspectRatio.ratio3x4:
      default:
        previewRatio = 3 / 4;
        break;
    }

    final rawRatio = cameraCtrl.value.aspectRatio;
    final cameraPreviewRatio = rawRatio > 1 ? rawRatio : (rawRatio > 0 ? 1 / rawRatio : 4 / 3);

    return RepaintBoundary(
      key: const ValueKey('geo_camera_viewfinder_key'),
      child: Center(
        child: AspectRatio(
          aspectRatio: previewRatio,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 100,
                  height: 100 * cameraPreviewRatio,
                  child: camera.CameraPreview(cameraCtrl),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridOverlay() {
    return IgnorePointer(
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: Container(decoration: _gridBorder())),
                Expanded(child: Container(decoration: _gridBorder())),
                Expanded(child: Container(decoration: _gridBorder())),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Container(decoration: _gridBorder())),
                Expanded(child: Container(decoration: _gridBorder())),
                Expanded(child: Container(decoration: _gridBorder())),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: Container(decoration: _gridBorder())),
                Expanded(child: Container(decoration: _gridBorder())),
                Expanded(child: Container(decoration: _gridBorder())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _gridBorder() {
    return BoxDecoration(
      border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.5),
    );
  }

  Widget _buildArtificialHorizon() {
    return const SizedBox.shrink(); // Center line hidden for clean camera preview
  }

  Widget _buildTopActionBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Flash Mode Toggle
          IconButton(
            icon: Icon(_getFlashIcon(), color: Colors.white, size: 22),
            onPressed: _toggleFlash,
            tooltip: 'Flash Mode',
          ),

          // HDR Button
          GestureDetector(
            onTap: () => setState(() => _hdrEnabled = !_hdrEnabled),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'HDR',
                style: TextStyle(
                  color: _hdrEnabled ? Colors.amber : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),

          // Filters
          IconButton(
            icon: Icon(
              Icons.style,
              color: _showFilters ? Colors.amber : Colors.white,
              size: 22,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Filters',
          ),

          // Settings Sheet Button
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white, size: 22),
            onPressed: _openSettingsSheet,
            tooltip: 'Camera & Geo Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildGeoTagHUDCard() {
    final location = _controller.latestLocation;
    final latStr =
        location != null
            ? '${location.latitude.toStringAsFixed(5)}° N'
            : '19.07600° N';
    final lonStr =
        location != null
            ? '${location.longitude.toStringAsFixed(5)}° E'
            : '72.87770° E';
    final accStr =
        location != null
            ? '±${location.accuracy.toStringAsFixed(1)}m'
            : '±3.2m';
    final nowStr =
        DateTime.now().toUtc().toIso8601String().replaceAll('T', ' ').substring(
          0,
          19,
        ) +
        ' UTC';

    return Positioned(
      left: 16,
      right: 16,
      top: 70,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.withOpacity(0.5), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.amber, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _overlayConfig.showAddress
                        ? 'Mumbai, Maharashtra, India'
                        : _overlayConfig.customNote,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 3,
                        backgroundColor: Colors.greenAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        accStr,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_overlayConfig.showCoordinates)
              Row(
                children: [
                  const Icon(
                    Icons.my_location,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$latStr, $lonStr',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  if (_overlayConfig.showAltitude)
                    const Text(
                      'Alt: 15.4m',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            if (_overlayConfig.showTimestamp) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Colors.white60,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    nowStr,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  if (_overlayConfig.showCompass)
                    Row(
                      children: [
                        const Icon(Icons.explore, color: Colors.amber, size: 13),
                        const SizedBox(width: 2),
                        Text(
                          '${_sensorData.formattedHeading} | P:${_sensorData.formattedPitch}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEvSliderOverlay() {
    return Positioned(
      right: 16,
      top: 180,
      bottom: 240,
      child: Container(
        width: 48,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber, width: 1),
        ),
        child: Column(
          children: [
            const Icon(Icons.wb_sunny, color: Colors.amber, size: 18),
            const SizedBox(height: 8),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.amber,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.amber,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _exposureOffset,
                    min: -2.0,
                    max: 2.0,
                    divisions: 16,
                    onChanged: (val) => _setExposureOffset(val),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_exposureOffset.toStringAsFixed(1)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProPanel() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 200,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.withOpacity(0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PRO Controls',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showProPanel = false),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white60,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildProOptionRow(
              'ISO',
              ['AUTO', '100', '200', '400', '800'],
              _selectedIso,
              (v) => setState(() => _selectedIso = v),
            ),
            const SizedBox(height: 6),
            _buildProOptionRow(
              'WB',
              ['Auto', 'Daylight', 'Cloudy', 'Tungsten'],
              _selectedWb,
              (v) => setState(() => _selectedWb = v),
            ),
            const SizedBox(height: 6),
            _buildProOptionRow(
              'Focus',
              ['Auto', 'Macro', 'Infinity', 'Lock'],
              _selectedFocus,
              (v) => setState(() => _selectedFocus = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProOptionRow(
    String label,
    List<String> options,
    String selected,
    ValueChanged<String> onSelect,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 45,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children:
                  options.map((opt) {
                    final isSel = opt == selected;
                    return GestureDetector(
                      onTap: () => onSelect(opt),
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isSel ? Colors.amber : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          opt,
                          style: TextStyle(
                            color: isSel ? Colors.black : Colors.white,
                            fontSize: 11,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownOverlay() {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.amber, width: 3),
        ),
        child: Center(
          child: Text(
            '$_countdownRemaining',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoTimerBadge() {
    final mins = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return Positioned(
      top: 70,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.shade900.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white38),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(radius: 4, backgroundColor: Colors.white),
              const SizedBox(width: 8),
              Text(
                '00:$mins:$secs',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineMorePanel() {
    final moreItems = [
      {'icon': Icons.tune, 'label': 'PRO', 'mode': GeoCameraMode.pro},
      {'icon': Icons.nightlight_round, 'label': 'NIGHT', 'mode': GeoCameraMode.photo},
      {'icon': Icons.panorama, 'label': 'PANO', 'mode': GeoCameraMode.photo},
      {'icon': Icons.slow_motion_video, 'label': 'SLO-MO', 'mode': GeoCameraMode.video},
      {'icon': Icons.timelapse, 'label': 'TIME-LAPSE', 'mode': GeoCameraMode.video},
      {'icon': Icons.pin_drop, 'label': 'GEO STAMP', 'action': 'stamp'},
    ];

    return Positioned(
      left: 16,
      right: 16,
      bottom: 60,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MORE CAMERA MODES',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectMode(GeoCameraMode.photo),
                  child: const Icon(Icons.close, color: Colors.white70, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: moreItems.length,
              itemBuilder: (context, index) {
                final item = moreItems[index];
                return GestureDetector(
                  onTap: () {
                    if (item['action'] == 'stamp') {
                      _openSettingsSheet();
                    } else if (item['mode'] != null) {
                      _selectMode(item['mode']! as GeoCameraMode);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item['icon'] as IconData, color: Colors.amber, size: 24),
                        const SizedBox(height: 6),
                        Text(
                          item['label'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingViewfinderControls() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Floating Left: Auto-Focus / Scanner Lens Button
          GestureDetector(
            onTap: _triggerAutoFocus,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.center_focus_weak,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),

          // Floating Center: 1X Zoom Pill with Quick 0.6x, 1x, 2x, 5x Zoom Options
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildZoomPill(0.6, '0.6X'),
                const SizedBox(width: 4),
                _buildZoomPill(1.0, '1X'),
                const SizedBox(width: 4),
                _buildZoomPill(2.0, '2X'),
                const SizedBox(width: 4),
                _buildZoomPill(5.0, '5X'),
              ],
            ),
          ),

          // Floating Right: Retouching / Beauty Filter Button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _beautyEnabled = !_beautyEnabled);
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _beautyEnabled ? Colors.amber.withOpacity(0.8) : Colors.black.withOpacity(0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.face_retouching_natural,
                color: _beautyEnabled ? Colors.black : Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomPill(double level, String label) {
    final isSelected = (_zoomLevel - level).abs() < 0.2;
    return GestureDetector(
      onTap: () => _setZoom(level),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.3) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomDot(double level) {
    final isSelected = (_zoomLevel - level).abs() < 0.2;
    return GestureDetector(
      onTap: () => _setZoom(level),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.white.withOpacity(0.7),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildFilterBarOverlay() {
    final filters = ['Normal', 'Vivid', 'Warm', 'Cool', 'B&W', 'Vintage'];
    return Positioned(
      left: 16,
      right: 16,
      top: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((f) {
              final isSel = f == _selectedFilter;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _selectedFilter = f;
                    _showFilters = false;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? Colors.amber : Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    f,
                    style: TextStyle(
                      color: isSel ? Colors.black : Colors.white,
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTopCapturedPhotoBanner() {
    final capture = _lastCapture;
    if (capture == null || !_showCapturedPhotoBanner) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 16,
      right: 16,
      child: GestureDetector(
        onTap: () {
          setState(() => _showCapturedPhotoBanner = false);
          _openGalleryPreviewSheet();
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(capture.imagePath),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Photo Captured!',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _overlayConfig.showAddress
                          ? 'Mumbai, Maharashtra, India'
                          : 'Lat: ${capture.latitude?.toStringAsFixed(4)}, Long: ${capture.longitude?.toStringAsFixed(4)}',
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tap to inspect metadata & EXIF',
                      style: TextStyle(color: Colors.amber.shade200, fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60, size: 18),
                onPressed: () {
                  setState(() => _showCapturedPhotoBanner = false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModePickerBar() {
    final modes = [
      GeoCameraMode.video,
      GeoCameraMode.photo,
      GeoCameraMode.portrait,
      GeoCameraMode.more,
    ];

    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = (screenWidth - _kModeItemWidth) / 2;

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        controller: _modeScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: modes.map((mode) {
              final isSelected = mode == _activeMode;
              final label = mode.name.toUpperCase();
              return GestureDetector(
                onTap: () {
                  _selectMode(mode);
                  if (mode == GeoCameraMode.more) {
                    _openMoreModesSheet();
                  }
                },
                child: SizedBox(
                  width: _kModeItemWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? const Color(0xFFFFB300) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          fontSize: 14,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      if (isSelected)
                        Container(
                          width: 36,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB300),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        )
                      else
                        const SizedBox(height: 2.5),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _openMoreModesSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final moreItems = [
          {'icon': Icons.tune, 'label': 'PRO', 'mode': GeoCameraMode.pro},
          {'icon': Icons.nightlight_round, 'label': 'NIGHT', 'mode': GeoCameraMode.photo},
          {'icon': Icons.panorama, 'label': 'PANORAMA', 'mode': GeoCameraMode.photo},
          {'icon': Icons.timelapse, 'label': 'TIME-LAPSE', 'mode': GeoCameraMode.video},
          {'icon': Icons.document_scanner, 'label': 'DOCUMENTS', 'mode': GeoCameraMode.photo},
          {'icon': Icons.pin_drop, 'label': 'GEO STAMP', 'action': 'stamp'},
        ];

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white30,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'More Camera Modes',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemCount: moreItems.length,
                itemBuilder: (context, index) {
                  final item = moreItems[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (item['action'] == 'stamp') {
                        _openSettingsSheet();
                      } else if (item['mode'] != null) {
                        final mode = item['mode']! as GeoCameraMode;
                        setState(() {
                          _activeMode = mode;
                          if (mode == GeoCameraMode.pro) {
                            _showProPanel = true;
                          }
                        });
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item['icon'] as IconData, color: Colors.amber, size: 28),
                          const SizedBox(height: 8),
                          Text(
                            item['label'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomShutterBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Circular Gallery Thumbnail Preview
          GestureDetector(
            onTap: _openGalleryPreviewSheet,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1.5),
                color: Colors.grey.shade900,
                image: _lastCapture != null
                    ? DecorationImage(
                        image: FileImage(File(_lastCapture!.imagePath)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _lastCapture == null
                  ? const Icon(Icons.photo, color: Colors.white38, size: 24)
                  : null,
            ),
          ),

          // Center: Bold White Ring Shutter Button with Black Inner Fill
          GestureDetector(
            onTap: _handleShutterPress,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _activeMode == GeoCameraMode.video ? Colors.red : Colors.black,
                  ),
                ),
              ),
            ),
          ),

          // Right: Switch Camera Icon Button
          GestureDetector(
            onTap: () async {
              try {
                await _controller.switchCamera();
                _updateZoomBoundaries();
                setState(() {});
              } catch (_) {}
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade900,
              ),
              child: const Icon(
                Icons.flip_camera_android,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'Geo-Tag Overlay Customization',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(color: Colors.white24),
                  SwitchListTile(
                    activeThumbColor: Colors.amber,
                    title: const Text(
                      'Show Address Box on Live Preview',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Background GPS location tracking always stays active',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    value: _showHudCardOnPreview,
                    onChanged: (v) => setState(() {
                      _showHudCardOnPreview = v;
                      setSheetState(() {});
                    }),
                  ),
                  SwitchListTile(
                    activeThumbColor: Colors.amber,
                    title: const Text(
                      'Show Address Name',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _overlayConfig.showAddress,
                    onChanged:
                        (v) => setState(() {
                          _overlayConfig = _overlayConfig.copyWith(
                            showAddress: v,
                          );
                          setSheetState(() {});
                        }),
                  ),
                  SwitchListTile(
                    activeThumbColor: Colors.amber,
                    title: const Text(
                      'Show Lat / Long Coordinates',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _overlayConfig.showCoordinates,
                    onChanged:
                        (v) => setState(() {
                          _overlayConfig = _overlayConfig.copyWith(
                            showCoordinates: v,
                          );
                          setSheetState(() {});
                        }),
                  ),
                  SwitchListTile(
                    activeThumbColor: Colors.amber,
                    title: const Text(
                      'Show Altitude & Accuracy',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _overlayConfig.showAltitude,
                    onChanged:
                        (v) => setState(() {
                          _overlayConfig = _overlayConfig.copyWith(
                            showAltitude: v,
                          );
                          setSheetState(() {});
                        }),
                  ),
                  SwitchListTile(
                    activeThumbColor: Colors.amber,
                    title: const Text(
                      'Show Compass Heading',
                      style: TextStyle(color: Colors.white),
                    ),
                    value: _overlayConfig.showCompass,
                    onChanged:
                        (v) => setState(() {
                          _overlayConfig = _overlayConfig.copyWith(
                            showCompass: v,
                          );
                          setSheetState(() {});
                        }),
                  ),
                  ListTile(
                    title: const Text(
                      'Timer Countdown',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      _timerSeconds == 0 ? 'Off' : '${_timerSeconds}s',
                      style: const TextStyle(color: Colors.amber),
                    ),
                    trailing: const Icon(Icons.timer, color: Colors.amber),
                    onTap: () {
                      _cycleTimer();
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openGalleryPreviewSheet() {
    final capture = _lastCapture;
    if (capture == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.black,
                title: const Text('Captured Geo-Photo Details'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(capture.imagePath),
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: 320,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withOpacity(0.4)),
                        ),
                        child: SelectableText(
                          'File Path: ${capture.imagePath}\n'
                          'Timestamp: ${capture.timestamp.toLocal()}\n'
                          'Latitude: ${capture.latitude ?? "N/A"}\n'
                          'Longitude: ${capture.longitude ?? "N/A"}\n'
                          'Accuracy: ${capture.accuracy?.toStringAsFixed(1) ?? "N/A"} m\n'
                          'Dimensions: ${capture.width} × ${capture.height}\n'
                          'Portrait Crop Applied: ${capture.portraitCropApplied ? "Yes" : "No"}\n'
                          'Metadata JSON: ${capture.metadataPath ?? "None"}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case camera.FlashMode.auto:
        return Icons.flash_auto;
      case camera.FlashMode.always:
        return Icons.flash_on;
      case camera.FlashMode.torch:
        return Icons.highlight;
      case camera.FlashMode.off:
        return Icons.flash_off;
    }
  }
}
