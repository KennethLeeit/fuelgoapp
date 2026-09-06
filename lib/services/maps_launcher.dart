import 'package:url_launcher/url_launcher.dart';

class MapsLauncher {
  static Uri directionsUri({
    required double lat,
    required double lng,
  }) {
    _validateCoordinates(lat, lng);
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
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
