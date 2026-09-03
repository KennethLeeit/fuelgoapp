import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'location_service.dart';
import 'osm_reverse_geocoding_service.dart' show ReverseGeocodingService, GeocodeTarget;

/// Fetches real fuel station locations from OpenStreetMap via the free,
/// keyless Overpass API. No signup, no API key, no billing.
/// Docs: https://wiki.openstreetmap.org/wiki/Overpass_API
///
/// Queries all public Overpass mirrors at once and takes whichever
/// responds successfully first, instead of trying them one at a time —
/// mirrors can be slow or momentarily rate-limited, and racing them keeps
/// the worst case bounded by one timeout instead of the sum of three.
class OsmFuelService {
  // Confirmed via current OSM community reporting: overpass-api.de (the
  // "primary" instance) has been actively fingerprinting and 406-blocking
  // "programmatic-looking" traffic since an ongoing AI-scraper abuse
  // crackdown — exactly what an app's requests look like. It's kept only
  // as a last-resort third option, not the default. kumi.systems and
  // private.coffee are independently-run mirrors that don't apply the same
  // aggressive bot filtering and are the documented reliable picks for
  // real client apps in 2026.
  static const List<String> _endpoints = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass-api.de/api/interpreter',
  ];

  // A descriptive User-Agent (with a contact-style suffix) and explicit
  // Accept/Accept-Encoding headers are specifically what overpass-api.de's
  // bot filter checks for — missing any of these makes a 406 more likely
  // even against the friendlier mirrors.
  static const Map<String, String> _headers = {
    'User-Agent': 'FuelGoApp/1.0 (+https://github.com/fuelgo-app; nearby station finder)',
    'Accept': 'application/json, */*',
    'Accept-Encoding': 'gzip, deflate, br',
  };

  /// GETs [query] (as a `?data=` param) from every endpoint in [_endpoints]
  /// simultaneously and resolves with the first successful (HTTP 200)
  /// response. Only fails if every endpoint fails or times out.
  ///
  /// Uses GET rather than POST specifically for Flutter Web — several
  /// public Overpass mirrors now reject POST's CORS preflight outright
  /// (HTTP 406). GET with only simple headers doesn't trigger a preflight
  /// at all. Fuel stations have MyGeoMap as a non-Overpass primary source
  /// so this mattered less here, but this OSM enrichment path benefits
  /// from the same fix for consistency/reliability.
  static Future<http.Response> _raceEndpoints(String query, Duration timeout) {
    final completer = Completer<http.Response>();
    var remaining = _endpoints.length;
    Object? lastError;

    void fail(Object error) {
      lastError = error;
      remaining--;
      if (remaining == 0 && !completer.isCompleted) {
        completer.completeError(
            lastError ?? Exception('Could not reach any Overpass endpoint'));
      }
    }

    for (final endpoint in _endpoints) {
      final uri = Uri.parse(endpoint).replace(queryParameters: {'data': query});
      http
          .get(
            uri,
            headers: _headers,
          )
          .timeout(timeout)
          .then((res) {
            if (completer.isCompleted) return;
            if (res.statusCode == 200) {
              completer.complete(res);
            } else {
              fail(
                  Exception('Overpass ($endpoint) returned HTTP ${res.statusCode}'));
            }
          }, onError: (Object e) {
            if (completer.isCompleted) return;
            debugPrint('[OsmFuelService] $endpoint failed: $e');
            fail(e);
          });
    }

    return completer.future;
  }

  static Future<List<FuelStation>> fetchNearby(AppLatLng center,
      {double radiusKm = 15,
      int limit = 40,
      bool resolveAddresses = true}) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '''
[out:json][timeout:10];
(
  node["amenity"="fuel"](around:$radiusM,${center.lat},${center.lng});
  way["amenity"="fuel"](around:$radiusM,${center.lat},${center.lng});
);
out center $limit;
''';
    final res = await _raceEndpoints(query, const Duration(seconds: 10));
    final stations = _parse(json.decode(res.body), center);

    // Fills in a real street address (via reverse geocoding) for the
    // closest few stations that OSM has no addr:* tags for at all —
    // Navigate already works fine off the coordinates regardless, this
    // is purely so the address line has something truthful to show
    // instead of the "not listed" placeholder. Capped and cached inside
    // the service itself so this never blocks the fetch for long or
    // exceeds Nominatim's rate limit.
    if (!resolveAddresses) return stations;
    final targets = stations
        .map((s) => GeocodeTarget(
              id: s.id,
              latitude: s.latitude,
              longitude: s.longitude,
              name: s.name,
              hasReadableAddress: s.hasReadableAddress,
              currentAddress: s.hasReadableAddress ? s.address : null,
            ))
        .toList();
    final resolved = await ReverseGeocodingService.resolveMissing(targets);
    return stations.map((s) {
      final address = resolved[s.id];
      return address == null ? s : _withAddress(s, address);
    }).toList(growable: false);
  }

  static Future<List<FuelStation>> fetchByIds(List<String> ids,
      {AppLatLng? reference}) async {
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
[out:json][timeout:15];
(
  ${clauses.join('\n  ')}
);
out center;
''';
    final res = await _raceEndpoints(query, const Duration(seconds: 15));
    return _parse(json.decode(res.body), reference ?? const AppLatLng(0, 0));
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
      bool truthy(String key) {
        final v = tags[key]?.toString().toLowerCase();
        return v != null && v != 'no' && v != '0' && v != 'false';
      }

      if (truthy('fuel:diesel')) fuelTypes.add('Diesel');
      if (truthy('fuel:octane_95') || truthy('fuel:ron95')) {
        fuelTypes.add('RON95');
      }
      if (truthy('fuel:octane_97') || truthy('fuel:ron97')) {
        fuelTypes.add('RON97');
      }

      final services = <String>[];
      if (tags['shop'] != null && tags['shop'].toString().toLowerCase() != 'no') {
        services.add('Shop');
      }
      if (truthy('toilets') || tags['toilets:wheelchair'] != null) services.add('Toilet');
      if (truthy('car_wash') || tags['shop'] == 'car_wash') services.add('Car Wash');
      if (truthy('atm') || tags['amenity'] == 'atm') services.add('ATM');
      if (truthy('fuel:lpg')) services.add('LPG');
      if (truthy('compressed_air') || truthy('air_conditioning')) services.add('Air Pump');
      if (truthy('internet_access')) services.add('WiFi');

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

  /// FuelStation's fields are final, so attaching a reverse-geocoded
  /// address means rebuilding the object — same pattern as
  /// mygeomap_fuel_service.dart's _withAddress.
  static FuelStation _withAddress(FuelStation station, String address) {
    return FuelStation(
      id: station.id,
      name: station.name,
      brand: station.brand,
      address: address,
      latitude: station.latitude,
      longitude: station.longitude,
      distanceKm: station.distanceKm,
      open24Hours: station.open24Hours,
      openingHoursRaw: station.openingHoursRaw,
      fuelTypes: station.fuelTypes,
      services: station.services,
      brandColor: station.brandColor,
      imageUrl: station.imageUrl,
      website: station.website,
    );
  }
}
