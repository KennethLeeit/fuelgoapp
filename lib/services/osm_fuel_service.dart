import 'dart:convert';
import 'package:flutter/foundation.dart';
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
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
  ];

  static Future<List<FuelStation>> fetchNearby(AppLatLng center,
      {double radiusKm = 15, int limit = 40}) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '''
[out:json][timeout:8];
(
  node["amenity"="fuel"](around:$radiusM,${center.lat},${center.lng});
  way["amenity"="fuel"](around:$radiusM,${center.lat},${center.lng});
);
out center $limit;
''';

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final res = await http.post(
          Uri.parse(endpoint),
          headers: const {'User-Agent': 'FuelGo/1.0 (nearby station finder)'},
          body: {'data': query},
        ).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) {
          lastError =
              Exception('Overpass ($endpoint) returned ${res.statusCode}');
          continue;
        }
        return _parse(json.decode(res.body), center);
      } catch (e) {
        lastError = e;
        debugPrint('[OsmFuelService] $endpoint failed: $e');
        continue;
      }
    }
    throw lastError ?? Exception('Could not reach any Overpass endpoint');
  }

  /// Fetches specific fuel stations by their OSM ids (e.g. "node/12345"),
  /// regardless of where they are relative to any particular location.
  /// Used to resolve favourited OSM-sourced stations that aren't in the
  /// current nearby-search results (e.g. favourited from another device,
  /// or simply because the user isn't near it anymore).
  static Future<List<FuelStation>> fetchByIds(List<String> ids, {AppLatLng? reference}) async {
    final nodeIds = <String>[];
    final wayIds = <String>[];
    for (final id in ids) {
      final parts = id.split('/');
      if (parts.length != 2) continue;
      if (parts[0] == 'node') nodeIds.add(parts[1]);
      if (parts[0] == 'way') wayIds.add(parts[1]);
    }
    if (nodeIds.isEmpty && wayIds.isEmpty) return const [];

    final clauses = <String>[
      if (nodeIds.isNotEmpty) 'node(id:${nodeIds.join(',')});',
      if (wayIds.isNotEmpty) 'way(id:${wayIds.join(',')});',
    ];
    final query = '''
[out:json][timeout:20];
(
  ${clauses.join('\n  ')}
);
out center;
''';

    Object? lastError;
    for (final endpoint in _endpoints) {
      try {
        final res = await http.post(
          Uri.parse(endpoint),
          headers: const {'User-Agent': 'FuelGo/1.0 (nearby station finder)'},
          body: {'data': query},
        ).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          lastError = Exception('Overpass ($endpoint) returned ${res.statusCode}');
          continue;
        }
        return _parse(json.decode(res.body), reference ?? const AppLatLng(0, 0));
      } catch (e) {
        lastError = e;
        debugPrint('[OsmFuelService] $endpoint failed: $e');
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
      final name =
          (tags['name'] ?? tags['brand'] ?? 'Unnamed fuel station') as String;

      double? lat = (e['lat'] as num?)?.toDouble();
      double? lng = (e['lon'] as num?)?.toDouble();
      if (lat == null && e['center'] != null) {
        lat = (e['center']['lat'] as num?)?.toDouble();
        lng = (e['center']['lon'] as num?)?.toDouble();
      }
      if (lat == null || lng == null) continue;

      final fullAddress = tags['addr:full']?.toString().trim();
      final addressParts = [
        tags['addr:housenumber'],
        tags['addr:street'],
        tags['addr:place'],
        tags['addr:suburb'],
        tags['addr:city'],
        tags['addr:state'],
        tags['addr:postcode'],
      ]
          .where((p) => p != null && p.toString().trim().isNotEmpty)
          .map((p) => p.toString().trim())
          .toSet()
          .join(', ');
      final address =
          fullAddress?.isNotEmpty == true ? fullAddress! : addressParts;

      final openingHours = tags['opening_hours'] as String?;
      final open24 =
          openingHours == '24/7' ? true : (openingHours == null ? null : false);

      final fuelTypes = <String>[];
      if (tags['fuel:diesel'] == 'yes') fuelTypes.add('Diesel');
      if (tags['fuel:octane_95'] == 'yes') fuelTypes.add('RON95');
      if (tags['fuel:octane_97'] == 'yes') fuelTypes.add('RON97');
      final services = <String>[];
      if (tags['shop'] != null && tags['shop'] != 'no') services.add('Shop');
      if (tags['toilets'] == 'yes') services.add('Toilet');
      if (tags['car_wash'] == 'yes') services.add('Car Wash');
      if (tags['atm'] == 'yes') services.add('ATM');
      if (tags['fuel:lpg'] == 'yes') services.add('LPG');

      final imageUrl = _imageUrl(tags);
      final website = (tags['website'] ?? tags['contact:website'])?.toString();

      stations.add(FuelStation(
        id: '${e['type']}/${e['id']}',
        name: name,
        brand: tags['brand'] as String?,
        address: address.isNotEmpty ? address : 'Address not provided',
        latitude: lat,
        longitude: lng,
        open24Hours: open24,
        openingHoursRaw: openingHours,
        fuelTypes: fuelTypes,
        services: services,
        brandColor: colorForName(tags['brand'] as String? ?? name),
        imageUrl: imageUrl,
        website: website,
      ));
    }

    for (final s in stations) {
      s.distanceKm = double.parse(
        LocationService.distanceKm(center, AppLatLng(s.latitude, s.longitude))
            .toStringAsFixed(1),
      );
    }
    stations.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return stations;
  }

  static String? _imageUrl(Map<String, dynamic> tags) {
    final image = tags['image']?.toString().trim();
    if (image != null &&
        (image.startsWith('https://') || image.startsWith('http://'))) {
      return image;
    }
    final commons = (tags['wikimedia_commons'] ?? image)?.toString().trim();
    if (commons != null && commons.startsWith('File:')) {
      final fileName = commons.substring(5).replaceAll(' ', '_');
      return Uri.https(
        'commons.wikimedia.org',
        '/wiki/Special:Redirect/file/$fileName',
        {'width': '1000'},
      ).toString();
    }
    return null;
  }
}
