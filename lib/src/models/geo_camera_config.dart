import 'package:camera/camera.dart';

/// Desired image capture orientation.
enum GeoCameraOrientation {
  portrait,
  landscape,
}

/// Target output orientation for saved images.
enum GeoCameraOutputOrientation {
  /// Preserves natural orientation of the capture.
  natural,

  /// Forces all output images into portrait orientation (width < height).
  portrait,

  /// Converts and rotates all output images into landscape orientation (width > height).
  landscape,
}

/// How landscape pixels are cropped to produce a portrait image.
enum PortraitCropMode {
  /// Crop a centered 3:4 (or configured ratio) composition from landscape.
  centerCrop,

  /// Crop only enough from the sides to make landscape pixels portrait.
  preservePortrait,
}

/// Legacy image strategy retained for source compatibility.
@Deprecated('Use PortraitCropMode instead.')
enum PortraitProcessingStrategy { centerCrop, rotateToPortrait }

/// Configuration shared by the camera, location, and image pipeline.
class GeoCameraConfig {
  const GeoCameraConfig({
    this.resolutionPreset = ResolutionPreset.high,
    this.enableAudio = false,
    this.outputDirectory,
    PortraitCropMode portraitCropMode = PortraitCropMode.centerCrop,
    @Deprecated('Use portraitCropMode instead.')
    PortraitProcessingStrategy? portraitStrategy,
    this.portraitAspectRatio = 3 / 4,
    this.jpegQuality = 95,
    this.maxLocationAge = const Duration(seconds: 30),
    this.maxLocationAccuracy = 50,
    this.locationTimeout = const Duration(seconds: 3),
    this.locationInterval = const Duration(seconds: 5),
    this.locationDistanceFilter = 0,
    this.embedLocationInExif = false,
    this.writeMetadataJson = true,
    this.preserveNaturalOrientation = true,
    this.outputOrientation = GeoCameraOutputOrientation.natural,
  }) : portraitCropMode = portraitStrategy == null
           ? portraitCropMode
           : portraitStrategy == PortraitProcessingStrategy.centerCrop
           ? PortraitCropMode.centerCrop
           : PortraitCropMode.preservePortrait,
       portraitStrategy =
           portraitStrategy ??
           (portraitCropMode == PortraitCropMode.centerCrop
               ? PortraitProcessingStrategy.centerCrop
               : PortraitProcessingStrategy.rotateToPortrait),
       assert(portraitAspectRatio > 0 && portraitAspectRatio < 1),
       assert(jpegQuality >= 1 && jpegQuality <= 100),
       assert(maxLocationAccuracy > 0),
       assert(locationDistanceFilter >= 0);

  final ResolutionPreset resolutionPreset;
  final bool enableAudio;
  final String? outputDirectory;
  final PortraitCropMode portraitCropMode;

  /// Legacy setting; `rotateToPortrait` now uses a crop to avoid sideways scenes.
  @Deprecated('Use portraitCropMode instead.')
  final PortraitProcessingStrategy portraitStrategy;

  /// Portrait width divided by height; the default is 3:4.
  final double portraitAspectRatio;

  final int jpegQuality;
  final Duration maxLocationAge;
  final double maxLocationAccuracy;
  final Duration locationTimeout;
  final Duration locationInterval;
  final int locationDistanceFilter;
  final bool embedLocationInExif;
  final bool writeMetadataJson;
  final bool preserveNaturalOrientation;
  final GeoCameraOutputOrientation outputOrientation;
}
