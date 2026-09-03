import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'location_service.dart';
import 'ev_operator_utils.dart';
import 'osm_reverse_geocoding_service.dart' show ReverseGeocodingService, GeocodeTarget;

/// Fetches real EV charging station locations from OpenStreetMap via the
/// free, keyless Overpass API — same source and mirror-racing pattern as
/// [OsmFuelService]. No signup, no API key, no billing, ever.
/// OSM tag reference: https://wiki.openstreetmap.org/wiki/Tag:amenity%3Dcharging_station
class OsmEvChargerService {
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

  // A descriptive User-Agent (with a contact-style suffix) and explicit
  // Accept/Accept-Encoding headers are specifically what overpass-api.de's
  // bot filter checks for — missing any of these makes a 406 more likely
  // even against the friendlier mirrors. See _endpoints comment above.
  static const Map<String, String> _headers = {
    'User-Agent': 'FuelGoApp/1.0 (+https://github.com/fuelgo-app; nearby station finder)',
    'Accept': 'application/json, */*',
    'Accept-Encoding': 'gzip, deflate, br',
  };

  /// GETs [query] (as a `?data=` param) from every endpoint in [_endpoints]
  /// simultaneously and resolves with the first successful (HTTP 200)
  /// response. Only fails if every endpoint fails or times out — bounding
  /// the worst case to one timeout instead of the sum of trying each
  /// mirror in turn.
  ///
  /// Uses GET rather than POST specifically for Flutter Web: several
  /// public Overpass mirrors (overpass-api.de among them) have tightened
  /// their CORS policy and now reject POST's preflight OPTIONS request
  /// outright (HTTP 406), which silently killed every EV charger fetch on
  /// web while fuel stations kept working fine (their primary source is
  /// MyGeoMap, not Overpass — this only ever affected EV, which has no
  /// non-Overpass fallback). GET requests with only simple headers don't
  /// trigger a CORS preflight at all, sidestepping the issue entirely.
  /// Our queries are short (well under typical URL length limits), so GET
  /// works fine here.
  static Future<http.Response> _raceEndpoints(String query, Duration timeout) {
    final completer = Completer<http.Response>();
    var remaining = _endpoints.length;
    Object? lastError;

    void fail(Object error) {
      lastError = error;
      remaining--;
      if (remaining == 0 && !completer.isCompleted) {
        completer.completeError(lastError ?? Exception('Could not reach any Overpass endpoint'));
      }
    }

    for (final endpoint in _endpoints) {
      final uri = Uri.parse(endpoint).replace(queryParameters: {'data': query});
      http.get(
        uri,
        headers: _headers,
      ).timeout(timeout).then((res) {
        if (completer.isCompleted) return;
        if (res.statusCode == 200) {
          completer.complete(res);
        } else {
          // Surfacing the exact status (406 = bot-filtered, 429 = rate
          // limited, 504 = query too slow for that server right now) makes
          // future "why is this failing" debugging much faster than a bare
          // "could not load" would.
          fail(Exception('Overpass ($endpoint) returned HTTP ${res.statusCode}'));
        }
      }, onError: (Object e) {
        if (completer.isCompleted) return;
        debugPrint('[OsmEvChargerService] $endpoint failed: $e');
        fail(e);
      });
    }

    return completer.future;
  }

  static Future<List<EVCharger>> fetchNearby(
    AppLatLng center, {
    double radiusKm = 15,
    int limit = 40,
    bool resolveAddresses = true,
  }) async {
    final radiusM = (radiusKm * 1000).round();
    final query = '''
[out:json][timeout:10];
(
  node["amenity"="charging_station"](around:$radiusM,${center.lat},${center.lng});
  way["amenity"="charging_station"](around:$radiusM,${center.lat},${center.lng});
);
out center $limit;
''';
    final res = await _raceEndpoints(query, const Duration(seconds: 10));
    final chargers = _parse(json.decode(res.body), center);
    if (!resolveAddresses) return chargers;
    return resolveAddressesFor(chargers);
  }

  /// Resolves addresses for chargers that don't have a readable one yet,
  /// against an already-fetched list — used both by [fetchNearby] directly
  /// and by StationCacheService's background enrichment, which needs this
  /// step *without* re-running the Overpass query it's enriching the
  /// results of. Same idea as OsmFuelService: OSM chargers sometimes have
  /// coordinates but no addr:* tags at all; this just fills in a real
  /// address for the closest few so the address line has something
  /// truthful to show instead of "Address not available". Shares one
  /// app-wide throttle with the fuel-station lookups (see
  /// ReverseGeocodingService) so the two together still respect
  /// Nominatim's 1 req/sec limit.
  static Future<List<EVCharger>> resolveAddressesFor(List<EVCharger> chargers) async {
    final targets = chargers
        .map((c) => GeocodeTarget(
              id: c.id,
              latitude: c.latitude,
              longitude: c.longitude,
              name: c.name,
              hasReadableAddress: c.hasReadableAddress,
              currentAddress: c.hasReadableAddress ? c.address : null,
            ))
        .toList();
    final resolved = await ReverseGeocodingService.resolveMissing(targets);
    return chargers.map((c) {
      final address = resolved[c.id];
      return address == null ? c : _withAddress(c, address);
    }).toList(growable: false);
  }

  /// Fetches specific EV chargers by their OSM ids (e.g. "node/12345"),
  /// regardless of location. Used to resolve favourited chargers that
  /// aren't in the current nearby-search results.
  static Future<List<EVCharger>> fetchByIds(List<String> ids, {AppLatLng? reference}) async {
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

      final rawOperatorName = tags['operator'] as String?;
      // Normalised the same way as the Open Charge Map source, so an OSM
      // node tagged operator="Tesla Motors" gets the same badge/filter
      // grouping as an OCM POI tagged "Tesla, Inc.".
      final operatorName = normaliseEvOperator(rawOperatorName);
      final name = (tags['name'] ?? operatorName ?? rawOperatorName ?? 'EV Charger') as String;

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
      // Fallback: some nodes just tag a general max power without per-socket
      // detail, and different contributors use different key conventions
      // for it — check every common variant rather than just one or two.
      if (maxPower == 0) {
        final generalPower = double.tryParse('${tags['maxpower'] ?? tags['charging_station:power'] ?? tags['socket:power'] ?? tags['power'] ?? tags['charging_station:output'] ?? ''}');
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

  /// EVCharger's fields are final, so attaching a reverse-geocoded
  /// address means rebuilding the object — same pattern as
  /// OsmFuelService's _withAddress.
  static EVCharger _withAddress(EVCharger charger, String address) {
    return EVCharger(
      id: charger.id,
      name: charger.name,
      operatorName: charger.operatorName,
      address: address,
      latitude: charger.latitude,
      longitude: charger.longitude,
      distanceKm: charger.distanceKm,
      connectors: charger.connectors,
      maxPowerKw: charger.maxPowerKw,
      usageCostRaw: charger.usageCostRaw,
      operational: charger.operational,
    );
  }
}
