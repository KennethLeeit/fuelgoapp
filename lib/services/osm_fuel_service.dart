import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'location_service.dart';

/// Fetches real fuel station locations from OpenStreetMap via the free,
/// keyless Overpass API. No signup, no API key, no billing.
/// Docs: https://wiki.openstreetmap.org/wiki/Overpass_API
///
/// Tries multiple public Overpass mirrors in order and falls through to the
/// next one on failure/timeout/rate-limit, since the single default public
/// instance can be flaky or momentarily rate-limited.
class OsmFuelService {
  static const List<String> _endpoints = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

  static Future<List<FuelStation>> fetchNearby(AppLatLng center, {double radiusKm = 15, int limit = 40}) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '''
[out:json][timeout:20];
(
  node["amenity"="fuel"](around:$radiusM,${center.lat},${center.lng});
  way["amenity"="fuel"](around:$radiusM,${center.lat},${center.lng});
);
out center $limit;
''';

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final res = await http
            .post(Uri.parse(endpoint), body: {'data': query})
            .timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) {
          lastError = Exception('Overpass ($endpoint) returned ${res.statusCode}');
          continue;
        }
        return _parse(json.decode(res.body), center);
      } catch (e) {
        lastError = e;
        continue;
      }
    }
    throw lastError ?? Exception('Could not reach any Overpass endpoint');
  }

  static List<FuelStation> _parse(Map<String, dynamic> data, AppLatLng center) {
    final List<dynamic> elements = data['elements'] ?? [];
    final stations = <FuelStation>[];

    for (final e in elements) {
      final tags = Map<String, dynamic>.from(e['tags'] ?? {});
      final name = (tags['name'] ?? tags['brand'] ?? 'Fuel Station') as String;

      double? lat = (e['lat'] as num?)?.toDouble();
      double? lng = (e['lon'] as num?)?.toDouble();
      if (lat == null && e['center'] != null) {
        lat = (e['center']['lat'] as num?)?.toDouble();
        lng = (e['center']['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final addressParts = [
        tags['addr:housenumber'],
        tags['addr:street'],
        tags['addr:city'],
        tags['addr:postcode'],
      ].where((p) => p != null && p.toString().isNotEmpty).join(', ');

      final openingHours = tags['opening_hours'] as String?;
      final open24 = openingHours == '24/7' ? true : (openingHours == null ? null : false);

      final fuelTypes = <String>[];
      if (tags['fuel:diesel'] == 'yes') fuelTypes.add('Diesel');
      if (tags['fuel:octane_95'] == 'yes') fuelTypes.add('RON95');
      if (tags['fuel:octane_97'] == 'yes') fuelTypes.add('RON97');
      if (fuelTypes.isEmpty) fuelTypes.addAll(['RON95', 'RON97', 'Diesel']); // typical default in MY

      final services = <String>[];
      if (tags['shop'] == 'convenience') services.add('Shop');
      if (tags['toilets'] == 'yes') services.add('Toilet');
      if (tags['car_wash'] == 'yes') services.add('Car Wash');
      if (tags['atm'] == 'yes') services.add('ATM');
      if (tags['fuel:lpg'] == 'yes') services.add('LPG');

      stations.add(FuelStation(
        id: '${e['type']}/${e['id']}',
        name: name,
        brand: tags['brand'] as String?,
        address: addressParts.isNotEmpty ? addressParts : 'Address not available',
        latitude: lat,
        longitude: lng,
        open24Hours: open24,
        openingHoursRaw: openingHours,
        fuelTypes: fuelTypes,
        services: services,
        brandColor: colorForName(tags['brand'] as String? ?? name),
      ));
    }

    for (final s in stations) {
      s.distanceKm = double.parse(
        LocationService.distanceKm(center, AppLatLng(s.latitude, s.longitude)).toStringAsFixed(1),
      );
    }
    stations.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return stations;
  }
}