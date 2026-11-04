import 'src/geo_camera_controller.dart';
import 'src/models/geo_camera_config.dart';
import 'geo_camera_pro_platform_interface.dart';

export 'src/exceptions/geo_camera_exception.dart';
export 'src/models/capture_result.dart';
export 'src/models/geo_camera_config.dart';
export 'src/models/location_data.dart';
export 'src/models/sensor_data.dart';
export 'src/sensors/sensor_manager.dart';
export 'src/ui/geo_camera_view.dart';

/// Public API for camera capture with continuous GPS tracking.
class GeoCameraPro extends GeoCameraController {
  /// Creates an instance with optional camera, location, and processing config.
  GeoCameraPro({super.config = const GeoCameraConfig()});

  /// Returns the host platform version.
  Future<String?> getPlatformVersion() =>
      GeoCameraProPlatform.instance.getPlatformVersion();
}
