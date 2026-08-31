import 'package:geolocator/geolocator.dart';

/// Lightweight lat/lng pair used throughout the app's data services.
class AppLatLng {
  final double lat;
  final double lng;
  const AppLatLng(this.lat, this.lng);
}

/// Thrown when the device's real location genuinely can't be determined
/// (location services off, permission denied, GPS timeout, etc). There is
/// deliberately no silent fallback to a hardcoded city here — showing the
/// wrong place as if it were the user's real location is worse than
/// clearly surfacing that location isn't available yet.
class LocationUnavailableException implements Exception {
  final String message;
  const LocationUnavailableException(this.message);
  @override
  String toString() => message;
}

/// Resolves the user's real GPS location. Callers should catch
/// [LocationUnavailableException] and show a retry/permission prompt
/// rather than assuming a location is always available.
class LocationService {
  // Kicked off early (e.g. while the user is still on the login screen) so
  // the GPS fix / permission prompt is already in flight by the time the
  // map screen actually needs it. Subsequent calls to getCurrentLocation()
  // reuse this in-flight/completed future instead of starting a fresh fix.
  static Future<AppLatLng>? _prewarmed;

  /// Starts resolving the device location ahead of time. Safe to call
  /// multiple times — only the first call actually triggers a fetch.
  static void prewarm() {
    _prewarmed ??= _resolveLocation();
  }

  static Future<AppLatLng> getCurrentLocation() {
    if (_prewarmed != null) return _prewarmed!;
    return _resolveLocation();
  }

  /// Returns a location instantly if the OS already has a cached fix on
  /// hand (no GPS wait, no permission prompt needed) — otherwise falls
  /// through to a full resolution, which may prompt for permission and
  /// wait for a fresh GPS fix. Throws [LocationUnavailableException] if
  /// location genuinely can't be determined either way.
  static Future<AppLatLng> getQuickLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return AppLatLng(last.latitude, last.longitude);
    } catch (_) {
      // Fall through to a full resolution below.
    }
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
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const LocationUnavailableException(
          'Location permission is needed to show the map and nearby stations.');
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return AppLatLng(pos.latitude, pos.longitude);
  }

  static double distanceKm(AppLatLng a, AppLatLng b) {
    return Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng) / 1000;
  }
}
