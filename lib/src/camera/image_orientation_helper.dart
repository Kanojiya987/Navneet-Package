import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// Helper to automatically fix image orientation issues from EXIF metadata across devices.
class ImageOrientationHelper {
  static Future<File> fixOrientation(File imageFile) async {
    try {
      final tempDir = await getTemporaryDirectory();

      final targetPath =
          '${tempDir.path}/fixed_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final XFile? result =
          await FlutterImageCompress.compressAndGetFile(
        imageFile.path,
        targetPath,
        quality: 92,
        autoCorrectionAngle: true,
        keepExif: false,
      );

      if (result != null) {
        return File(result.path);
      }

      return imageFile;
    } catch (e) {
      // Return the original image if correction fails.
      return imageFile;
    }
  }
}
