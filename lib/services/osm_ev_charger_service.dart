import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'location_service.dart';

/// Fetches real EV charging station locations from OpenStreetMap via the
/// free, keyless Overpass API — same source and same reliability pattern
/// (multi-mirror fallback) as [OsmFuelService]. No signup, no API key, no
/// billing, ever.
/// OSM tag reference: https://wiki.openstreetmap.org/wiki/Tag:amenity%3Dcharging_station
class OsmEvChargerService {
  static const List<String> _endpoints = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

  // OSM tags for the connector types we recognize, mapped to a friendly label.
  static const Map<String, String> _connectorTags = {
    'socket:type2': 'Type 2',
    'socket:type2_combo': 'CCS2',
    'socket:chademo': 'CHAdeMO',
    'socket:tesla_supercharger': 'Tesla Supercharger',
    'socket:tesla_standard': 'Tesla',
    'socket:schuko': 'Schuko',
    'socket:type1': 'Type 1',
    'socket:type1_combo': 'CCS1',
  };

  static Future<List<EVCharger>> fetchNearby(AppLatLng center, {double radiusKm = 15, int limit = 40}) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '''
[out:json][timeout:20];
(
  node["amenity"="charging_station"](around:$radiusM,${center.lat},${center.lng});
  way["amenity"="charging_station"](around:$radiusM,${center.lat},${center.lng});
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

  static List<EVCharger> _parse(Map<String, dynamic> data, AppLatLng center) {
    final List<dynamic> elements = data['elements'] ?? [];
    final chargers = <EVCharger>[];

    for (final e in elements) {
      final tags = Map<String, dynamic>.from(e['tags'] ?? {});

      double? lat = (e['lat'] as num?)?.toDouble();
      double? lng = (e['lon'] as num?)?.toDouble();
      if (lat == null && e['center'] != null) {
        lat = (e['center']['lat'] as num?)?.toDouble();
        lng = (e['center']['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final operatorName = tags['operator'] as String?;
      final name = (tags['name'] ?? operatorName ?? 'EV Charger') as String;

      final addressParts = [
        tags['addr:housenumber'],
        tags['addr:street'],
        tags['addr:city'],
        tags['addr:postcode'],
      ].where((p) => p != null && p.toString().isNotEmpty).join(', ');

      final connectors = <String>[];
      double maxPower = 0;
      for (final entry in _connectorTags.entries) {
        final value = tags[entry.key];
        if (value != null && value != 'no' && value != '0') {
          connectors.add(entry.value);
          final powerTag = tags['${entry.key}:power'];
          final power = double.tryParse('$powerTag');
          if (power != null && power > maxPower) maxPower = power;
        }
      }
      // Fallback: some nodes just tag a general max power without per-socket detail.
      if (maxPower == 0) {
        final generalPower = double.tryParse('${tags['maxpower'] ?? tags['charging_station:power'] ?? ''}');
        if (generalPower != null) maxPower = generalPower;
      }

      String? usageCost;
      if (tags['fee'] == 'yes') {
        usageCost = 'Paid \u2014 check operator app';
      } else if (tags['fee'] == 'no') {
        usageCost = 'Free';
      }

      bool? operational;
      final access = tags['access'] as String?;
      if (tags['opening_hours'] == 'closed' || access == 'no' || access == 'private') {
        operational = false;
      } else if (tags.containsKey('amenity')) {
        operational = true; // present in live OSM data = presumed active
      }

      chargers.add(EVCharger(
        id: '${e['type']}/${e['id']}',
        name: name,
        operatorName: operatorName,
        address: addressParts.isNotEmpty ? addressParts : 'Address not available',
        latitude: lat,
        longitude: lng,
        connectors: connectors,
        maxPowerKw: maxPower > 0 ? maxPower.round() : null,
        usageCostRaw: usageCost,
        operational: operational,
      ));
    }

    for (final c in chargers) {
      c.distanceKm = double.parse(
        LocationService.distanceKm(center, AppLatLng(c.latitude, c.longitude)).toStringAsFixed(1),
      );
    }
    chargers.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return chargers;
  }
}
