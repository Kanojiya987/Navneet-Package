/// A GPS fix and its original acquisition timestamp.
class LocationData {
  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  /// Creates a location from the map sent by the native location provider.
  factory LocationData.fromMap(Map<Object?, Object?> map) {
    final latitude = (map['latitude'] as num?)?.toDouble();
    final longitude = (map['longitude'] as num?)?.toDouble();
    final accuracy = (map['accuracy'] as num?)?.toDouble();
    final timestampValue = map['timestamp'];
    final timestamp = timestampValue is num
        ? DateTime.fromMillisecondsSinceEpoch(
            timestampValue.toInt(),
            isUtc: true,
          )
        : timestampValue is String
        ? DateTime.parse(timestampValue).toUtc()
        : null;

    if (latitude == null ||
        longitude == null ||
        accuracy == null ||
        timestamp == null ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !accuracy.isFinite ||
        accuracy < 0) {
      throw const FormatException(
        'Native location data is invalid or incomplete.',
      );
    }

    return LocationData(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      timestamp: timestamp,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };
}
