import 'package:geolocator/geolocator.dart';

/// Lightweight lat/lng pair used throughout the app's data services.
class AppLatLng {
  final double lat;
  final double lng;
  const AppLatLng(this.lat, this.lng);
}

/// Resolves the user's real GPS location when available, and falls back
/// gracefully to Kuala Lumpur city center when location services are off,
/// permission is denied, or anything else goes wrong (e.g. desktop/web
/// without location support, indoor GPS timeout, etc).
class LocationService {
  static const AppLatLng fallback = AppLatLng(3.1390, 101.6869); // KL city center

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

  /// Returns a location instantly, without waiting for a fresh GPS fix or
  /// any permission prompt: the device's last cached position if the OS
  /// has one on hand, otherwise the KL fallback. Meant for painting the
  /// map immediately; pair with getCurrentLocation() to silently upgrade
  /// to a precise fix right after.
  static Future<AppLatLng> getQuickLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return AppLatLng(last.latitude, last.longitude);
    } catch (_) {}
    return fallback;
  }

  static Future<AppLatLng> _resolveLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return fallback;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return fallback;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return AppLatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return fallback;
    }
  }

  /// True if the point returned is the fallback (i.e. real GPS wasn't used).
  static bool isFallback(AppLatLng p) => p.lat == fallback.lat && p.lng == fallback.lng;

  static double distanceKm(AppLatLng a, AppLatLng b) {
    return Geolocator.distanceBetween(a.lat, a.lng, b.lat, b.lng) / 1000;
  }
}
