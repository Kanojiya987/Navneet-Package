import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geo_camera_pro/src/camera/portrait_processor.dart';
import 'package:geo_camera_pro/src/exceptions/geo_camera_exception.dart';
import 'package:geo_camera_pro/src/models/geo_camera_config.dart';
import 'package:geo_camera_pro/src/models/location_data.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

void main() {
  late Directory temporaryDirectory;
  final captureTime = DateTime(2026, 11, 1, 10, 30, 45);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'geo_camera_pro_test_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<PortraitProcessingResult> processBytes(
    List<int> bytes,
    String outputName, {
    GeoCameraConfig config = const GeoCameraConfig(),
    LocationData? location,
  }) async {
    final inputPath = path.join(temporaryDirectory.path, 'source-$outputName');
    final outputPath = path.join(temporaryDirectory.path, outputName);
    await File(inputPath).writeAsBytes(bytes);
    return PortraitProcessor(config).process(
      inputPath: inputPath,
      outputPath: outputPath,
      location: location,
      captureTimestamp: captureTime,
    );
  }

  Future<PortraitProcessingResult> processImage(
    img.Image image,
    String outputName, {
    GeoCameraConfig config = const GeoCameraConfig(),
    LocationData? location,
  }) async {
    return processBytes(
      img.encodeJpg(image, quality: 100),
      outputName,
      config: config,
      location: location,
    );
  }

  Future<PortraitProcessingResult> process({
    required int width,
    required int height,
    required String outputName,
    GeoCameraConfig config = const GeoCameraConfig(),
    LocationData? location,
  }) async {
    return processImage(
      _scene(width: width, height: height),
      outputName,
      config: config,
      location: location,
    );
  }

  test('preserves natural landscape orientation by default', () async {
    final result = await process(
      width: 800,
      height: 600,
      outputName: 'natural-landscape.jpg',
    );
    final output = await _decodeOutput(result.imagePath);

    expect(result.originalWidth, 800);
    expect(result.originalHeight, 600);
    expect(output.width, 800);
    expect(output.height, 600);
    expect(output.width, greaterThan(output.height));
    expect(result.cropApplied, isFalse);
  });

  test(
    'center crops landscape pixels to the configured portrait ratio',
    () async {
      final result = await process(
        width: 800,
        height: 600,
        outputName: 'landscape.jpg',
        config: const GeoCameraConfig(preserveNaturalOrientation: false),
      );
      final output = await _decodeOutput(result.imagePath);

      expect(result.originalWidth, 800);
      expect(result.originalHeight, 600);
      expect(output.width, 450);
      expect(output.height, 600);
      expect(output.width, lessThan(output.height));
      expect(result.cropApplied, isTrue);
      expect(output.exif.imageIfd.orientation, isNull);
    },
  );

  test(
    'reverse landscape crops symmetrically without rotating the scene',
    () async {
      final input = _scene(width: 800, height: 600)
        ..exif.imageIfd.orientation = 8;
      final result = await processImage(
        input,
        'reverse-landscape.jpg',
        config: const GeoCameraConfig(
          outputOrientation: GeoCameraOutputOrientation.portrait,
          preserveNaturalOrientation: false,
        ),
      );
      final output = await _decodeOutput(result.imagePath);

      expect(result.width, 600);
      expect(result.height, 800);
      expect(result.cropApplied, isFalse);
      expect(output.getPixel(100, 100).g, greaterThan(200));
    },
  );

  test('preserves portrait pixels and original aspect ratio', () async {
    final result = await process(
      width: 400,
      height: 800,
      outputName: 'portrait.jpg',
    );
    expect(result.width, 400);
    expect(result.height, 800);
    expect(result.cropApplied, isFalse);
  });

  for (final orientation in <int>[1, 2, 3, 4, 5, 6, 7, 8]) {
    test('applies EXIF orientation $orientation exactly once', () async {
      final source = _scene(width: 800, height: 600)
        ..exif.imageIfd.orientation = orientation;
      final encodedSource = img.encodeJpg(source, quality: 100);
      final decodedSource = img.decodeImage(encodedSource)!;
      var expected = img.bakeOrientation(decodedSource);
      if (expected.width >= expected.height) {
        final width = (expected.height * 0.75).floor();
        expected = img.copyCrop(
          expected,
          x: (expected.width - width) ~/ 2,
          y: 0,
          width: width,
          height: expected.height,
        );
      }

      final result = await processBytes(
        encodedSource,
        'orientation-$orientation.jpg',
        config: const GeoCameraConfig(
          outputOrientation: GeoCameraOutputOrientation.natural,
          preserveNaturalOrientation: false,
        ),
      );
      final output = await _decodeOutput(result.imagePath);
      final expectedDecoded = img.decodeImage(
        img.encodeJpg(expected, quality: 95),
      )!;

      expect(output.width, expectedDecoded.width);
      expect(output.height, expectedDecoded.height);
      expect(output.width, lessThan(output.height));
      expect(output.exif.imageIfd.orientation, isNull);
      _expectSamePixels(output, expectedDecoded);
    });
  }

  test(
    'handles a very wide landscape without out-of-bounds cropping',
    () async {
      final result = await process(
        width: 2400,
        height: 100,
        outputName: 'very-wide.jpg',
        config: const GeoCameraConfig(preserveNaturalOrientation: false),
      );

      expect(result.width, 75);
      expect(result.height, 100);
      expect(result.cropApplied, isTrue);
      expect(result.width, lessThan(result.height));
    },
  );

  test(
    'handles a small square by a centered crop without stretching',
    () async {
      final source = _scene(width: 2, height: 2);
      final result = await processImage(
        source,
        'small.jpg',
        config: const GeoCameraConfig(preserveNaturalOrientation: false),
      );
      final output = await _decodeOutput(result.imagePath);

      expect(output.width, 1);
      expect(output.height, 2);
      expect(result.cropApplied, isTrue);
    },
  );

  test('preservePortrait mode minimally crops landscape sides', () async {
    final result = await processImage(
      _scene(width: 800, height: 600),
      'preserve-mode.jpg',
      config: const GeoCameraConfig(
        preserveNaturalOrientation: false,
        portraitCropMode: PortraitCropMode.preservePortrait,
      ),
    );

    expect(result.width, 599);
    expect(result.height, 600);
    expect(result.cropApplied, isTrue);
  });

  test('preserves and embeds GPS metadata in JPEG EXIF', () async {
    final result = await process(
      width: 400,
      height: 600,
      outputName: 'gps.jpg',
      config: const GeoCameraConfig(
        embedLocationInExif: true,
        outputOrientation: GeoCameraOutputOrientation.portrait,
      ),
      location: LocationData(
        latitude: 45.5,
        longitude: -73.6,
        accuracy: 3,
        timestamp: DateTime.utc(2026, 11, 1),
      ),
    );

    final output = await _decodeOutput(result.imagePath);
    expect(output.exif.gpsIfd.gpsLatitude, closeTo(45.5, 0.001));
    expect(output.exif.gpsIfd.gpsLongitude, closeTo(73.6, 0.001));
    expect(output.exif.gpsIfd.gpsLatitudeRef, 'N');
    expect(output.exif.gpsIfd.gpsLongitudeRef, 'W');
  });

  test('preserves existing GPS and capture timestamp EXIF', () async {
    final source = _scene(width: 400, height: 600)
      ..exif.gpsIfd.setGpsLocation(latitude: 40.7, longitude: -74.0)
      ..exif.exifIfd['DateTimeOriginal'] = '2024:03:04 05:06:07';
    final result = await processImage(
      source,
      'existing-metadata.jpg',
      config: const GeoCameraConfig(
        outputOrientation: GeoCameraOutputOrientation.portrait,
      ),
    );
    final output = await _decodeOutput(result.imagePath);

    expect(output.exif.gpsIfd.gpsLatitude, closeTo(40.7, 0.001));
    expect(output.exif.gpsIfd.gpsLongitude, closeTo(74.0, 0.001));
    expect(
      output.exif.exifIfd['DateTimeOriginal']?.toString(),
      '2024:03:04 05:06:07',
    );
  });

  test('adds capture timestamp metadata if source has none', () async {
    final result = await process(
      width: 400,
      height: 600,
      outputName: 'timestamp.jpg',
      config: const GeoCameraConfig(
        outputOrientation: GeoCameraOutputOrientation.portrait,
      ),
    );
    final output = await _decodeOutput(result.imagePath);

    expect(
      output.exif.exifIfd['DateTimeOriginal']?.toString(),
      '2026:11:01 10:30:45',
    );
  });

  test('reports corrupted images as a typed processing error', () async {
    final inputPath = path.join(temporaryDirectory.path, 'corrupted.jpg');
    await File(inputPath).writeAsString('not an image');

    await expectLater(
      const PortraitProcessor(GeoCameraConfig()).process(
        inputPath: inputPath,
        outputPath: path.join(temporaryDirectory.path, 'output.jpg'),
        captureTimestamp: captureTime,
      ),
      throwsA(isA<ImageProcessingException>()),
    );
  });
}

img.Image _scene({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final top = y < height ~/ 2;
      final left = x < width ~/ 2;
      image.setPixelRgb(
        x,
        y,
        top ? (left ? 240 : 20) : (left ? 20 : 240),
        top ? (left ? 20 : 230) : (left ? 40 : 230),
        top ? (left ? 20 : 30) : (left ? 240 : 20),
      );
    }
  }
  return image;
}

Future<img.Image> _decodeOutput(String imagePath) async =>
    img.decodeImage(await File(imagePath).readAsBytes())!;

void _expectSamePixels(img.Image actual, img.Image expected) {
  for (var y = 0; y < actual.height; y++) {
    for (var x = 0; x < actual.width; x++) {
      final actualPixel = actual.getPixel(x, y);
      final expectedPixel = expected.getPixel(x, y);
      expect(actualPixel.r, closeTo(expectedPixel.r, 1));
      expect(actualPixel.g, closeTo(expectedPixel.g, 1));
      expect(actualPixel.b, closeTo(expectedPixel.b, 1));
    }
  }
}
