/// Real-time sensor readings including gyroscope, pitch, roll, and compass heading.
class SensorData {
  const SensorData({
    this.pitch = 0.0,
    this.roll = 0.0,
    this.heading = 0.0,
    this.gyroX = 0.0,
    this.gyroY = 0.0,
    this.gyroZ = 0.0,
  });

  /// Device pitch angle in degrees (-180 to 180).
  final double pitch;

  /// Device roll angle in degrees (-180 to 180).
  final double roll;

  /// Compass heading in degrees (0 to 360).
  final double heading;

  /// Gyroscope rotation speed on X axis in rad/s.
  final double gyroX;

  /// Gyroscope rotation speed on Y axis in rad/s.
  final double gyroY;

  /// Gyroscope rotation speed on Z axis in rad/s.
  final double gyroZ;

  /// Human-readable cardinal direction (N, NE, E, SE, S, SW, W, NW).
  String get compassDirection {
    final norm = (heading % 360 + 360) % 360;
    if (norm >= 337.5 || norm < 22.5) return 'N';
    if (norm >= 22.5 && norm < 67.5) return 'NE';
    if (norm >= 67.5 && norm < 112.5) return 'E';
    if (norm >= 112.5 && norm < 157.5) return 'SE';
    if (norm >= 157.5 && norm < 202.5) return 'S';
    if (norm >= 202.5 && norm < 247.5) return 'SW';
    if (norm >= 247.5 && norm < 292.5) return 'W';
    return 'NW';
  }

  /// Formatted compass string, e.g. "142° SE".
  String get formattedHeading => '${heading.toStringAsFixed(0)}° $compassDirection';

  /// Formatted pitch string, e.g. "-2.4°".
  String get formattedPitch => '${pitch.toStringAsFixed(1)}°';

  /// Formatted roll string, e.g. "1.2°".
  String get formattedRoll => '${roll.toStringAsFixed(1)}°';

  Map<String, dynamic> toJson() => {
        'pitch': pitch,
        'roll': roll,
        'heading': heading,
        'gyroX': gyroX,
        'gyroY': gyroY,
        'gyroZ': gyroZ,
        'compassDirection': compassDirection,
      };
}
