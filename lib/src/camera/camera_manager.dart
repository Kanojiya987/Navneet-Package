import 'package:camera/camera.dart' as camera;

import '../exceptions/geo_camera_exception.dart';
import '../models/geo_camera_config.dart';

/// Owns the Flutter camera controller and its initialization lifecycle.
class CameraManager {
  CameraManager(this.config);

  final GeoCameraConfig config;
  camera.CameraController? _controller;
  camera.CameraLensDirection _lensDirection = camera.CameraLensDirection.back;

  camera.CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  camera.CameraLensDirection get lensDirection => _lensDirection;

  /// Initializes the requested camera, preferring the rear lens by default.
  Future<void> initialize({
    camera.CameraLensDirection lensDirection = camera.CameraLensDirection.back,
  }) async {
    if (isInitialized && _lensDirection == lensDirection) return;

    await dispose();
    try {
      final cameras = await camera.availableCameras();
      if (cameras.isEmpty) {
        throw const CameraException('No camera is available on this device.');
      }

      final selected = cameras.where(
        (description) => description.lensDirection == lensDirection,
      );
      final description = selected.isNotEmpty ? selected.first : cameras.first;
      _lensDirection = description.lensDirection;

      final controller = camera.CameraController(
        description,
        config.resolutionPreset,
        enableAudio: config.enableAudio,
        imageFormatGroup: camera.ImageFormatGroup.jpeg,
      );
      _controller = controller;
      await controller.initialize();
    } on camera.CameraException catch (error) {
      await dispose();
      if (_isPermissionError(error.code)) {
        throw CameraPermissionException(error.description ?? error.code);
      }
      throw CameraException(
        error.description ?? 'Failed to initialize the camera.',
        code: error.code,
        details: error,
      );
    } on CameraException {
      rethrow;
    } catch (error) {
      await dispose();
      throw CameraException('Failed to initialize the camera.', details: error);
    }
  }

  /// Releases the current camera and initializes the opposite lens.
  Future<void> switchCamera() async {
    final nextDirection = _lensDirection == camera.CameraLensDirection.back
        ? camera.CameraLensDirection.front
        : camera.CameraLensDirection.back;
    await initialize(lensDirection: nextDirection);
  }

  /// Captures a still image from the initialized camera.
  Future<camera.XFile> takePicture() async {
    final current = _controller;
    if (current == null || !current.value.isInitialized) {
      throw const CameraException('Camera has not been initialized.');
    }

    try {
      return await current.takePicture();
    } on camera.CameraException catch (error) {
      if (_isPermissionError(error.code)) {
        throw CameraPermissionException(error.description ?? error.code);
      }
      throw CameraException(
        error.description ?? 'Failed to capture an image.',
        code: error.code,
        details: error,
      );
    }
  }

  /// Releases camera resources.
  Future<void> dispose() async {
    final current = _controller;
    _controller = null;
    if (current != null) {
      await current.dispose();
    }
  }

  bool _isPermissionError(String code) =>
      code.toLowerCase().contains('permission') ||
      code.toLowerCase().contains('denied');
}
