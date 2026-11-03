import 'location_data.dart';

/// Whether a usable location was attached to the capture.
enum CaptureGpsStatus { available, unavailable }

/// Details about the saved image and the GPS fix associated with its capture.
class CaptureResult {
  const CaptureResult({
    required this.imagePath,
    required this.timestamp,
    this.location,
    this.metadataPath,
    this.gpsError,
    this.originalWidth,
    this.originalHeight,
    this.width,
    this.height,
    this.portraitCropApplied = false,
  });

  /// Absolute path of the physically portrait-normalized JPEG.
  final String imagePath;

  /// Time recorded immediately before the camera shutter request.
  final DateTime timestamp;

  /// The most recent GPS fix that met the configured freshness/accuracy rules.
  final LocationData? location;

  /// Absolute path of the JSON sidecar, when written.
  final String? metadataPath;

  /// Error message explaining why GPS could not be associated, if applicable.
  final String? gpsError;

  /// Dimensions of the camera file before orientation normalization.
  final int? originalWidth;
  final int? originalHeight;

  /// Verified dimensions of the saved JPEG.
  final int? width;
  final int? height;

  /// Whether pixels were cropped to produce portrait dimensions.
  final bool portraitCropApplied;

  CaptureGpsStatus get gpsStatus => location == null
      ? CaptureGpsStatus.unavailable
      : CaptureGpsStatus.available;

  double? get latitude => location?.latitude;
  double? get longitude => location?.longitude;
  double? get accuracy => location?.accuracy;
  DateTime? get locationTimestamp => location?.timestamp;

  Map<String, Object?> toJson() => <String, Object?>{
    'imagePath': imagePath,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'locationTimestamp': locationTimestamp?.toUtc().toIso8601String(),
    'metadataPath': metadataPath,
    'gpsStatus': gpsStatus.name,
    'gpsError': gpsError,
    'originalWidth': originalWidth,
    'originalHeight': originalHeight,
    'width': width,
    'height': height,
    'portraitCropApplied': portraitCropApplied,
  };
}
