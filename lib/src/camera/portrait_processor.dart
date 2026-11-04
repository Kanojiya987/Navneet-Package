import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../exceptions/geo_camera_exception.dart';
import '../models/geo_camera_config.dart';
import '../models/location_data.dart';

/// Decodes and physically normalizes a captured image on a worker isolate.
class PortraitProcessor {
  const PortraitProcessor(this.config);

  final GeoCameraConfig config;

  /// Writes and verifies a physically portrait-oriented JPEG at [outputPath].
  Future<PortraitProcessingResult> process({
    required String inputPath,
    required String outputPath,
    LocationData? location,
    required DateTime captureTimestamp,
    int? deviceOrientationIndex,
    GeoCameraOrientation? forcedOrientation,
    int? physicalOrientationDegrees,
  }) async {
    try {
      final result = await compute<Map<String, Object?>, Map<String, Object?>>(
        _processPortraitImage,
        <String, Object?>{
          'inputPath': inputPath,
          'outputPath': outputPath,
          'cropMode': config.portraitCropMode.index,
          'aspectRatio': config.portraitAspectRatio,
          'quality': config.jpegQuality,
          'embedLocation': config.embedLocationInExif,
          'latitude': location?.latitude,
          'longitude': location?.longitude,
          'captureTimestamp': captureTimestamp.toIso8601String(),
          'preserveNaturalOrientation': config.preserveNaturalOrientation,
          'deviceOrientationIndex': deviceOrientationIndex,
          'forcedOrientationIndex': forcedOrientation?.index,
          'physicalOrientationDegrees': physicalOrientationDegrees,
          'outputOrientationIndex': config.outputOrientation.index,
        },
      );
      return PortraitProcessingResult(
        imagePath: result['imagePath']! as String,
        originalWidth: result['originalWidth']! as int,
        originalHeight: result['originalHeight']! as int,
        width: result['width']! as int,
        height: result['height']! as int,
        cropApplied: result['cropApplied']! as bool,
      );
    } on GeoCameraException {
      rethrow;
    } catch (error) {
      throw ImageProcessingException(
        'Could not decode or normalize the captured image.',
        details: error,
      );
    }
  }
}

/// Image dimensions and crop information for a processed capture.
class PortraitProcessingResult {
  const PortraitProcessingResult({
    required this.imagePath,
    required this.originalWidth,
    required this.originalHeight,
    required this.width,
    required this.height,
    required this.cropApplied,
  });

  final String imagePath;
  final int originalWidth;
  final int originalHeight;
  final int width;
  final int height;
  final bool cropApplied;
}

Future<Map<String, Object?>> _processPortraitImage(
  Map<String, Object?> arguments,
) async {
  final inputPath = arguments['inputPath']! as String;
  final outputPath = arguments['outputPath']! as String;
  final decoded = img.decodeImage(await File(inputPath).readAsBytes());
  if (decoded == null) {
    throw const ImageProcessingException(
      'The captured image is corrupted or uses an unsupported format.',
    );
  }

  final originalWidth = decoded.width;
  final originalHeight = decoded.height;

  final preserveNaturalOrientation =
      arguments['preserveNaturalOrientation']! as bool;
  final deviceOrientationIndex =
      arguments['deviceOrientationIndex'] as int?;
  final forcedOrientationIndex =
      arguments['forcedOrientationIndex'] as int?;
  final physicalOrientationDegrees =
      arguments['physicalOrientationDegrees'] as int? ?? 0;
  final outputOrientationIndex =
      arguments['outputOrientationIndex'] as int? ??
      GeoCameraOutputOrientation.natural.index;
  final isPortraitDown = physicalOrientationDegrees == 180 || deviceOrientationIndex == 2;
  final isLandscapeRight = physicalOrientationDegrees == 270 || deviceOrientationIndex == 3;
  final isLandscapeLeft = physicalOrientationDegrees == 90 || deviceOrientationIndex == 1;
  final isHardwareLandscape = physicalOrientationDegrees == 90 || physicalOrientationDegrees == 270;
  final isDeviceLandscape = isHardwareLandscape || isLandscapeLeft || isLandscapeRight;

  debugPrint(
      'GeoCameraPro Debug: inputPath = $inputPath, originalWidth = $originalWidth, originalHeight = $originalHeight');
  debugPrint(
      'GeoCameraPro Debug: outputOrientationIndex = $outputOrientationIndex, forcedOrientationIndex = $forcedOrientationIndex, physicalOrientationDegrees = $physicalOrientationDegrees');

  // This is the only orientation transform. It also clears the orientation tag.
  var upright = img.bakeOrientation(decoded);
  debugPrint(
      'GeoCameraPro Debug: after bakeOrientation width = ${upright.width}, height = ${upright.height}');

  if (forcedOrientationIndex != null) {
    // 0: portrait, 1: landscape
    final wantLandscape = forcedOrientationIndex == 1;
    final isLandscape = upright.width > upright.height;
    debugPrint(
        'GeoCameraPro Debug: forcedOrientation wantLandscape = $wantLandscape, isLandscape = $isLandscape');

    if (wantLandscape && !isLandscape) {
      final rotationAngle = isLandscapeRight ? 270 : 90;
      var rotated = img.copyRotate(upright, angle: rotationAngle);
      if (rotated.width < rotated.height) {
        rotated = img.copyRotate(upright, angle: rotationAngle == 90 ? 270 : 90);
      }
      upright = rotated;
      debugPrint(
          'GeoCameraPro Debug: forced landscape rotation result width = ${upright.width}, height = ${upright.height}');
    } else if (!wantLandscape && isLandscape) {
      var rotated = img.copyRotate(upright, angle: 90);
      if (rotated.width > rotated.height) {
        rotated = img.copyRotate(upright, angle: 270);
      }
      upright = rotated;
      debugPrint(
          'GeoCameraPro Debug: forced portrait rotation result width = ${upright.width}, height = ${upright.height}');
    }
  } else if (outputOrientationIndex == GeoCameraOutputOrientation.landscape.index) {
    // Force Landscape output: convert portrait capture (width < height) to landscape (width > height)
    if (upright.width < upright.height) {
      debugPrint(
          'GeoCameraPro Debug: Rotating portrait capture into landscape output');
      final rotationAngle = isLandscapeRight ? 270 : 90;
      var rotated = img.copyRotate(upright, angle: rotationAngle);
      if (rotated.width < rotated.height) {
        rotated = img.copyRotate(upright, angle: rotationAngle == 90 ? 270 : 90);
      }
      upright = rotated;
      debugPrint(
          'GeoCameraPro Debug: Landscape result width = ${upright.width}, height = ${upright.height}');
    }
  } else if (outputOrientationIndex == GeoCameraOutputOrientation.portrait.index) {
    // Force Portrait output: convert landscape capture (width > height) to portrait (width < height)
    if (upright.width > upright.height) {
      debugPrint(
          'GeoCameraPro Debug: Rotating landscape capture into portrait output');
      var rotated = img.copyRotate(upright, angle: 90);
      if (rotated.width > upright.height) {
        rotated = img.copyRotate(upright, angle: 270);
      }
      upright = rotated;
    }
  } else if (preserveNaturalOrientation || outputOrientationIndex == GeoCameraOutputOrientation.natural.index) {
    final isImagePortrait = upright.width < upright.height;
    debugPrint(
        'GeoCameraPro Debug: isDeviceLandscape = $isDeviceLandscape, isPortraitDown = $isPortraitDown, isImagePortrait = $isImagePortrait');

    if (isPortraitDown) {
      // Device held upside down in portrait (180° / Portrait Down)
      debugPrint('GeoCameraPro Debug: Rotating 180° for upside-down portrait');
      if (isImagePortrait) {
        upright = img.copyRotate(upright, angle: 180);
      } else {
        upright = img.copyRotate(upright, angle: 270);
      }
    } else if (isLandscapeRight) {
      // Device held in reverse landscape (270° / Landscape Right)
      debugPrint('GeoCameraPro Debug: Normalizing for Landscape Right');
      if (isImagePortrait) {
        upright = img.copyRotate(upright, angle: 270);
      } else {
        upright = img.copyRotate(upright, angle: 180);
      }
    } else if (isLandscapeLeft) {
      // Device held in standard landscape (90° / Landscape Left)
      debugPrint('GeoCameraPro Debug: Normalizing for Landscape Left');
      if (isImagePortrait) {
        upright = img.copyRotate(upright, angle: 90);
      }
    }
  }

  bool cropApplied = false;

  if (preserveNaturalOrientation && upright.width >= upright.height) {
    // Preserve natural landscape orientation without forcing portrait crop/rotation.
  } else {
    final aspectRatio = arguments['aspectRatio']! as double;
    final cropMode = arguments['cropMode']! as int;
    var cropWidth = upright.width;
    final cropHeight = upright.height;
    if (upright.width >= upright.height) {
      final desiredWidth = cropMode == PortraitCropMode.preservePortrait.index
          ? upright.height - 1
          : (upright.height * aspectRatio).floor();
      cropWidth = math.min(upright.width, math.max(1, desiredWidth));
    }

    final cropX = (upright.width - cropWidth) ~/ 2;
    const cropY = 0;
    cropApplied =
        cropWidth != upright.width || cropHeight != upright.height;
    if (cropX < 0 ||
        cropY < 0 ||
        cropX + cropWidth > upright.width ||
        cropY + cropHeight > upright.height) {
      throw const ImageProcessingException(
        'Calculated portrait crop exceeds the image bounds.',
      );
    }
    if (cropWidth >= cropHeight) {
      throw const ImageProcessingException(
        'Portrait normalization did not produce portrait dimensions.',
      );
    }

    if (cropApplied) {
      upright = img.copyCrop(
        upright,
        x: cropX,
        y: cropY,
        width: cropWidth,
        height: cropHeight,
      );
    }
  }

  final captureTimestamp = DateTime.parse(
    arguments['captureTimestamp']! as String,
  ).toLocal();
  if (upright.exif.exifIfd['DateTimeOriginal'] == null) {
    upright.exif.exifIfd['DateTimeOriginal'] =
        '${captureTimestamp.year.toString().padLeft(4, '0')}:'
        '${captureTimestamp.month.toString().padLeft(2, '0')}:'
        '${captureTimestamp.day.toString().padLeft(2, '0')} '
        '${captureTimestamp.hour.toString().padLeft(2, '0')}:'
        '${captureTimestamp.minute.toString().padLeft(2, '0')}:'
        '${captureTimestamp.second.toString().padLeft(2, '0')}';
  }
  upright.exif.imageIfd.orientation = null;
  if (arguments['embedLocation']! as bool) {
    final latitude = arguments['latitude'] as double?;
    final longitude = arguments['longitude'] as double?;
    if (latitude != null && longitude != null) {
      upright.exif.gpsIfd.setGpsLocation(
        latitude: latitude,
        longitude: longitude,
      );
    }
  }

  final output = File(outputPath);
  await output.parent.create(recursive: true);
  final jpeg = img.encodeJpg(upright, quality: arguments['quality']! as int);
  await output.writeAsBytes(jpeg, flush: true);

  if (!preserveNaturalOrientation && upright.width >= upright.height) {
    throw const ImageProcessingException(
      'Saved JPEG failed dimension verification.',
    );
  }

  return <String, Object?>{
    'imagePath': output.path,
    'originalWidth': originalWidth,
    'originalHeight': originalHeight,
    'width': upright.width,
    'height': upright.height,
    'cropApplied': cropApplied,
  };
}
