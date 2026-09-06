import 'package:geolocator/geolocator.dart';

class AppLatLng {
  final double lat;
  final double lng;
  const AppLatLng(this.lat, this.lng);
}

class LocationUnavailableException implements Exception {
  final String message;
  const LocationUnavailableException(this.message);
  @override
  String toString() => message;
}

class LocationService {
  static Future<AppLatLng>? _prewarmed;
  static AppLatLng? _sharedCurrentLocation;
  static DateTime? _sharedCurrentLocationAt;

  static Future<AppLatLng> getSharedCurrentLocation({
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final cached = _sharedCurrentLocation;
    final cachedAt = _sharedCurrentLocationAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) <= maxAge) {
      return cached;
    }
    return getFreshCurrentLocation();
  }

  static void prewarm() {
    _prewarmed ??= _resolveLocation();
  }

  static Future<AppLatLng> getCurrentLocation() {
    if (_prewarmed != null) return _prewarmed!;
    return _resolveLocation();
  }

  static Future<AppLatLng> getFreshCurrentLocation() async {
    final request = _resolveLocation();
    _prewarmed = request;
    try {
      final location = await request;
      _sharedCurrentLocation = location;
      _sharedCurrentLocationAt = DateTime.now();
      return location;
    } finally {
      if (identical(_prewarmed, request)) _prewarmed = null;
    }
  }

  static AppLatLng? _remembered;

  static void rememberLocation(AppLatLng loc) {
    _remembered = loc;
  }

  static Future<AppLatLng> getQuickLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return AppLatLng(last.latitude, last.longitude);
    } catch (_) {}
    if (_remembered != null) return _remembered!;
    return getCurrentLocation();
  }

  static Future<AppLatLng> _resolveLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationUnavailableException(
          'Location services are turned off. Turn them on to see the map and nearby stations.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationUnavailableException(
          'Location permission is needed to show the map and nearby stations.');
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return AppLatLng(pos.latitude, pos.longitude);
  }

  static double distanceKm(AppLatLng a, AppLatLng b) {
    return Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng) / 1000;
  }
}
