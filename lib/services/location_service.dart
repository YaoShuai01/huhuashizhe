import 'package:flutter/foundation.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final String displayName;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.displayName = '当前位置',
  });
}

class LocationService {
  Future<LocationData?> getCurrentLocation() async {
    debugPrint('Location service: using default location (Shanghai)');
    return const LocationData(
      latitude: 31.23,
      longitude: 121.47,
      displayName: '上海市',
    );
  }
}
