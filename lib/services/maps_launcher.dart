import 'package:url_launcher/url_launcher.dart';

/// Launches turn-by-turn directions in the Google Maps app (or Google Maps
/// on the web as a fallback) for a given destination. This uses Google's
/// Maps URL scheme, which works without a Google Maps API key.
/// Docs: https://developers.google.com/maps/documentation/urls/get-started
class MapsLauncher {
  static Uri directionsUri({
    required double lat,
    required double lng,
  }) {
    _validateCoordinates(lat, lng);
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      // Coordinates only are intentional. Including a common station name
      // here lets Google geocode another branch with the same name, often in
      // Kuala Lumpur, instead of using the marker the user selected.
      'destination': '$lat,$lng',
      'travelmode': 'driving',
    });
  }

  static Uri locationUri({
    required double lat,
    required double lng,
  }) {
    _validateCoordinates(lat, lng);
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$lat,$lng',
    });
  }

  static Future<void> openDirections({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final uri = directionsUri(lat: lat, lng: lng);

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('Could not open Google Maps');
    }
  }

  /// Opens a location on the map (no route) — handy for "show on map" actions.
  static Future<void> openLocation({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final uri = locationUri(lat: lat, lng: lng);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('Could not open Google Maps');
    }
  }

  static void _validateCoordinates(double lat, double lng) {
    if (!lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      throw ArgumentError('Invalid map coordinates.');
    }
  }
}
