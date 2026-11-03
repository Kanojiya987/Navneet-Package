import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart' as camera;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../geo_camera_pro_platform_interface.dart';
import 'camera/camera_manager.dart';
import 'camera/image_orientation_helper.dart';
import 'camera/portrait_processor.dart';
import 'exceptions/geo_camera_exception.dart';
import 'location/location_manager.dart';
import 'models/capture_result.dart';
import 'models/geo_camera_config.dart';
import 'models/location_data.dart';

/// Coordinates camera, background location, and portrait capture workflows.
class GeoCameraController extends ChangeNotifier with WidgetsBindingObserver {
  GeoCameraController({GeoCameraConfig config = const GeoCameraConfig()})
    : config = config,
      _cameraManager = CameraManager(config),
      _locationManager = LocationManager(config),
      _portraitProcessor = PortraitProcessor(config) {
    _locationSubscription = _locationManager.updates.listen(
      _handleLocation,
      onError: _handleLocationError,
    );
  }

  final GeoCameraConfig config;
  final CameraManager _cameraManager;
  final LocationManager _locationManager;
  final PortraitProcessor _portraitProcessor;
  final ValueNotifier<bool> _trackingStatus = ValueNotifier<bool>(false);
  final StreamController<GeoCameraException> _errors =
      StreamController<GeoCameraException>.broadcast();

  StreamSubscription<LocationData>? _locationSubscription;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isCapturing = false;
  Completer<void>? _captureCompletion;
  Future<void>? _initializeOperation;
  Future<void>? _disposeOperation;
  Future<void> _lifecycleQueue = Future<void>.value();

  /// The currently initialized Flutter camera controller, if any.
  camera.CameraController? get cameraController => _cameraManager.controller;

  /// GPS fixes received while tracking is active.
  Stream<LocationData> get locationUpdates => _locationManager.updates;

  /// Asynchronous camera, location, and file pipeline failures.
  Stream<GeoCameraException> get errors => _errors.stream;

  /// Listen to this value to update tracking controls in a widget.
  ValueListenable<bool> get trackingStatus => _trackingStatus;

  bool get isTracking => _trackingStatus.value;
  bool get isInitialized => _isInitialized;
  LocationData? get latestLocation => _locationManager.latestLocation;

  /// Initializes the rear camera and registers app lifecycle handling.
  Future<void> initialize() {
    _ensureNotDisposed();
    if (_isInitialized) return Future<void>.value();
    return _initializeOperation ??= _initializeCamera().whenComplete(() {
      _initializeOperation = null;
    });
  }

  Future<void> _initializeCamera() async {
    await _cameraManager.initialize();
    if (_isDisposed) {
      await _cameraManager.dispose();
      return;
    }
    final nativeTracking = await _locationManager.restoreTrackingStatus();
    if (_isDisposed) {
      await _cameraManager.dispose();
      return;
    }
    _trackingStatus.value = nativeTracking;
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    notifyListeners();
  }

  /// Starts continuous native location updates.
  Future<void> startTracking() async {
    _ensureNotDisposed();
    await _locationManager.startTracking();
    if (!_isDisposed) _trackingStatus.value = true;
  }

  /// Stops continuous native location updates.
  Future<void> stopTracking() async {
    _ensureNotDisposed();
    await _locationManager.stopTracking();
    if (!_isDisposed) _trackingStatus.value = false;
  }

  /// Switches between front and rear cameras.
  Future<void> switchCamera() async {
    _ensureInitialized();
    if (_isCapturing) {
      throw const CameraException('Cannot switch cameras during a capture.');
    }
    await _cameraManager.switchCamera();
    if (!_isDisposed) notifyListeners();
  }

  /// Captures a photo, applies portrait normalization, and saves its metadata.
  Future<CaptureResult> capture({GeoCameraOrientation? orientation}) async {
    _ensureInitialized();
    if (_isCapturing) {
      throw const CameraException('A photo capture is already in progress.');
    }
    _isCapturing = true;
    final captureCompletion = Completer<void>();
    _captureCompletion = captureCompletion;
    try {
      final directory = await _resolveOutputDirectory();
      final capturedAt = DateTime.now().toUtc();
      final deviceOrientation = _cameraManager.controller?.value.deviceOrientation;
      final physicalDegrees =
          await GeoCameraProPlatform.instance.getPhysicalOrientationDegrees();
      debugPrint(
          'GeoCameraPro Debug: physicalDegrees = $physicalDegrees, deviceOrientation = $deviceOrientation, forcedOrientation = $orientation');
      final temporaryFile = await _cameraManager.takePicture();
      debugPrint('GeoCameraPro Debug: temporaryFile path = ${temporaryFile.path}');
      final correctedFile = await ImageOrientationHelper.fixOrientation(
        File(temporaryFile.path),
      );
      debugPrint('GeoCameraPro Debug: correctedFile path = ${correctedFile.path}');
      LocationData? location;
      String? gpsError;
      try {
        location = await _locationManager.locationForCapture();
      } on LocationTimeoutException catch (error) {
        gpsError = error.message;
        _errors.add(error);
      } on GeoCameraException catch (error) {
        gpsError = error.message;
        _errors.add(error);
      } catch (error) {
        final wrapped = GeoCameraException(
          'Could not obtain a location for this capture.',
          code: 'location_capture_error',
          details: error,
        );
        gpsError = wrapped.message;
        _errors.add(wrapped);
      }
      if (location == null && gpsError == null) {
        final unavailable = const LocationUnavailableException(
          'No fresh GPS fix is available; capture will continue without GPS.',
        );
        gpsError ??= unavailable.message;
        _errors.add(unavailable);
      }

      final fileName = 'geo_camera_${capturedAt.microsecondsSinceEpoch}.jpg';
      final imagePath = path.join(directory, fileName);
      final metadataPath = config.writeMetadataJson
          ? path.setExtension(imagePath, '.json')
          : null;

      try {
        final processed = await _portraitProcessor.process(
          inputPath: correctedFile.path,
          outputPath: imagePath,
          location: location,
          captureTimestamp: capturedAt,
          deviceOrientationIndex: deviceOrientation?.index,
          forcedOrientation: orientation,
          physicalOrientationDegrees: physicalDegrees,
        );
        final result = CaptureResult(
          imagePath: imagePath,
          timestamp: capturedAt,
          location: location,
          metadataPath: metadataPath,
          gpsError: gpsError,
          originalWidth: processed.originalWidth,
          originalHeight: processed.originalHeight,
          width: processed.width,
          height: processed.height,
          portraitCropApplied: processed.cropApplied,
        );

        if (metadataPath != null) {
          await File(metadataPath)
              .writeAsString(jsonEncode(result.toJson()), flush: true);
        }

        return result;
      } on GeoCameraException {
        rethrow;
      } on FileSystemException catch (error) {
        throw GeoCameraException(
          'Could not save the captured image or its metadata.',
          code: 'file_write_error',
          details: error,
        );
      } finally {
        await _deleteTemporaryFile(temporaryFile.path);
        if (correctedFile.path != temporaryFile.path) {
          await _deleteTemporaryFile(correctedFile.path);
        }
      }
    } finally {
      _isCapturing = false;
      captureCompletion.complete();
      _captureCompletion = null;
    }
  }

  /// Releases the camera, location service, and stream resources.
  @override
  Future<void> dispose() {
    final existingOperation = _disposeOperation;
    if (existingOperation != null) return existingOperation;
    if (_isDisposed) return Future<void>.value();
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
    super.dispose();
    return _disposeOperation = _disposeResources();
  }

  Future<void> _disposeResources() async {
    try {
      await _captureCompletion?.future;
      await _initializeOperation;
      await _lifecycleQueue;
    } finally {
      try {
        await _cameraManager.dispose();
      } finally {
        try {
          await _locationManager.dispose();
        } finally {
          await _locationSubscription?.cancel();
          await _errors.close();
          _trackingStatus.dispose();
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized || _isDisposed) return;
    if (state == AppLifecycleState.resumed) {
      _scheduleLifecycleOperation(_handleCameraResume);
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _scheduleLifecycleOperation(_handleCameraPause);
    }
  }

  void _scheduleLifecycleOperation(Future<void> Function() operation) {
    _lifecycleQueue = _lifecycleQueue.then((_) async {
      if (_isDisposed) return;
      try {
        await operation();
      } on GeoCameraException catch (error) {
        _errors.add(error);
      } catch (error) {
        _errors.add(
          CameraException('Camera lifecycle operation failed.', details: error),
        );
      }
    });
  }

  Future<void> _handleCameraResume() async {
    if (_cameraManager.controller == null) {
      await _cameraManager.initialize(
        lensDirection: _cameraManager.lensDirection,
      );
      if (!_isDisposed) notifyListeners();
    }
  }

  Future<void> _handleCameraPause() async {
    await _captureCompletion?.future;
    await _cameraManager.dispose();
    if (!_isDisposed) notifyListeners();
  }

  void _handleLocation(LocationData location) {
    if (!_isDisposed) notifyListeners();
  }

  void _handleLocationError(Object error, StackTrace stackTrace) {
    if (_isDisposed) return;
    _trackingStatus.value = false;
    if (error is GeoCameraException) {
      _errors.add(error);
    } else {
      _errors.add(
        GeoCameraException(
          'A location update failed.',
          code: 'location_stream_error',
          details: error,
        ),
      );
    }
  }

  Future<String> _resolveOutputDirectory() async {
    try {
      final configured = config.outputDirectory;
      if (configured != null) {
        final directory = Directory(configured).absolute;
        await directory.create(recursive: true);
        return directory.path;
      }

      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(path.join(documents.path, 'geo_camera_pro'));
      await directory.create(recursive: true);
      return directory.path;
    } on FileSystemException catch (error) {
      throw GeoCameraException(
        'Could not create the configured photo directory.',
        code: 'output_directory_error',
        details: error,
      );
    }
  }

  Future<void> _deleteTemporaryFile(String temporaryPath) async {
    try {
      final temporaryFile = File(temporaryPath);
      if (await temporaryFile.exists()) await temporaryFile.delete();
    } on FileSystemException catch (error) {
      _errors.add(
        GeoCameraException(
          'Could not remove the temporary camera image.',
          code: 'temporary_file_cleanup_error',
          details: error,
        ),
      );
    }
  }

  void _ensureInitialized() {
    _ensureNotDisposed();
    if (!_isInitialized || !_cameraManager.isInitialized) {
      throw const CameraException('Call initialize() before this operation.');
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('GeoCameraController has been disposed.');
    }
  }
}
