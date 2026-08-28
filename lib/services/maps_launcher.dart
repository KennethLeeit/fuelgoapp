import 'package:url_launcher/url_launcher.dart';

/// Launches turn-by-turn directions in the Google Maps app (or Google Maps
/// on the web as a fallback) for a given destination. This uses Google's
/// Maps URL scheme, which works without a Google Maps API key.
/// Docs: https://developers.google.com/maps/documentation/urls/get-started
class MapsLauncher {
  static Future<void> openDirections({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final destination = label != null && label.isNotEmpty
        ? Uri.encodeComponent('$label, $lat,$lng')
        : '$lat,$lng';

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=driving',
    );

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
    final query = label != null && label.isNotEmpty
        ? Uri.encodeComponent('$label, $lat,$lng')
        : '$lat,$lng';

    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw Exception('Could not open Google Maps');
    }
  }
}
