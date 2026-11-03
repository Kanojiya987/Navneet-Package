/// Base class for errors exposed by GeoCameraPro.
class GeoCameraException implements Exception {
  const GeoCameraException(
    this.message, {
    this.code = 'geo_camera_error',
    this.details,
  });

  final String message;
  final String code;
  final Object? details;

  @override
  String toString() => 'GeoCameraException($code): $message';
}

/// Camera setup or capture failed.
class CameraException extends GeoCameraException {
  const CameraException(
    super.message, {
    super.code = 'camera_error',
    super.details,
  });
}

/// Camera permission is missing or permanently denied.
class CameraPermissionException extends CameraException {
  const CameraPermissionException([super.message = 'Camera permission denied.'])
    : super(code: 'camera_permission_denied');
}

/// Location permission is missing or insufficient for the requested tracking.
class LocationPermissionException extends GeoCameraException {
  const LocationPermissionException([
    super.message = 'Location permission denied.',
  ]) : super(code: 'location_permission_denied');
}

/// The device cannot provide a usable location.
class LocationUnavailableException extends GeoCameraException {
  const LocationUnavailableException([
    super.message = 'Location services are unavailable.',
  ]) : super(code: 'location_unavailable');
}

/// No acceptable GPS fix arrived before the configured timeout.
class LocationTimeoutException extends GeoCameraException {
  const LocationTimeoutException([
    super.message = 'Timed out waiting for an acceptable GPS fix.',
  ]) : super(code: 'location_timeout');
}

/// The captured image could not be decoded or normalized.
class ImageProcessingException extends GeoCameraException {
  const ImageProcessingException(super.message, {super.details})
    : super(code: 'image_processing_error');
}
