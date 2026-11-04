import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../models/sensor_data.dart';

/// Manages continuous gyroscope, orientation, pitch, roll, and compass updates.
class SensorManager {
  SensorManager() {
    _initStreams();
  }

  final StreamController<SensorData> _controller =
      StreamController<SensorData>.broadcast();

  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<MagnetometerEvent>? _magSub;

  SensorData _latestData = const SensorData();

  /// Stream of live sensor updates.
  Stream<SensorData> get sensorUpdates => _controller.stream;

  /// Latest computed sensor data.
  SensorData get latestData => _latestData;

  double _accelX = 0, _accelY = 0, _accelZ = 1;
  double _magX = 0, _magY = 0, _magZ = 0;
  double _gyroX = 0, _gyroY = 0, _gyroZ = 0;

  void _initStreams() {
    runZonedGuarded(() {
      _gyroSub = gyroscopeEventStream().listen(
        (event) {
          _gyroX = event.x;
          _gyroY = event.y;
          _gyroZ = event.z;
          _emit();
        },
        onError: (Object _) {},
      );

      _accelSub = accelerometerEventStream().listen(
        (event) {
          _accelX = event.x;
          _accelY = event.y;
          _accelZ = event.z;
          _emit();
        },
        onError: (Object _) {},
      );

      _magSub = magnetometerEventStream().listen(
        (event) {
          _magX = event.x;
          _magY = event.y;
          _magZ = event.z;
          _emit();
        },
        onError: (Object _) {},
      );
    }, (Object _, StackTrace _) {
      // Ignore missing sensor platform channel exceptions in unit tests or unequipped devices.
    });
  }

  void _emit() {
    // Pitch & Roll computation from Accelerometer
    final pitchRad = math.atan2(
      -_accelX,
      math.sqrt(_accelY * _accelY + _accelZ * _accelZ),
    );
    final rollRad = math.atan2(_accelY, _accelZ);

    final pitchDeg = pitchRad * (180.0 / math.pi);
    final rollDeg = rollRad * (180.0 / math.pi);

    // Tilt-compensated Compass Heading computation from Accelerometer & Magnetometer
    double headingDeg = 0.0;
    if (_magX != 0 || _magY != 0 || _magZ != 0) {
      final cosRoll = math.cos(rollRad);
      final sinRoll = math.sin(rollRad);
      final cosPitch = math.cos(pitchRad);
      final sinPitch = math.sin(pitchRad);

      final xH = _magX * cosPitch + _magZ * sinPitch;
      final yH =
          _magX * sinRoll * sinPitch + _magY * cosRoll - _magZ * sinRoll * cosPitch;

      var headingRad = math.atan2(-yH, xH);
      if (headingRad < 0) headingRad += 2 * math.pi;
      headingDeg = headingRad * (180.0 / math.pi);
    }

    _latestData = SensorData(
      pitch: pitchDeg.isNaN ? 0.0 : pitchDeg,
      roll: rollDeg.isNaN ? 0.0 : rollDeg,
      heading: headingDeg.isNaN ? 0.0 : headingDeg,
      gyroX: _gyroX,
      gyroY: _gyroY,
      gyroZ: _gyroZ,
    );

    if (!_controller.isClosed) {
      _controller.add(_latestData);
    }
  }

  void dispose() {
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _magSub?.cancel();
    _controller.close();
  }
}
