import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'location_service.dart';

/// Fills in a readable street address for OSM-sourced fuel stations that
/// have coordinates but no addr:* tags at all (common in OpenStreetMap —
/// Navigate still works fine off the coordinates regardless, but the
/// address line on the detail screen otherwise has nothing truthful to
/// show, so it displays a placeholder instead).
///
/// Uses the free, keyless Nominatim reverse-geocoding endpoint — the same
/// OpenStreetMap service already used for place search in
/// smart_mobility_map_screen.dart. Mirrors the caching / nearest-neighbour
/// fallback design of MyGeoMapReverseGeocodingService, but with one
/// important difference: Nominatim's usage policy caps free/public use at
/// **one request per second**, and unlike the government MyGeoMap
/// endpoint that pattern was built for, firing several requests at once
/// risks the app's IP getting rate-limited or blocked outright. So unlike
/// MyGeoMapReverseGeocodingService's parallel batches, every lookup here
/// is funnelled through a single serialized queue with a guaranteed
/// ~1.1s gap between requests — no matter which screen (list, detail,
/// map) triggers it, or how many trigger it at once.
class OsmReverseGeocodingService {
  static const _endpoint = 'https://nominatim.openstreetmap.org/reverse';
  static const _storageKey = 'osm_reverse_address_cache_v1';
  static const _minGapBetweenRequests = Duration(milliseconds: 1100);

  static Map<String, String>? _cache;

  // Serializes every live network call through this chain, guaranteeing
  // at least _minGapBetweenRequests between requests app-wide — this is
  // what keeps the app compliant with Nominatim's policy regardless of
  // how many different widgets ask for a lookup at the same time.
  static Future<void> _throttleChain = Future.value();
  static DateTime? _lastRequestAt;

  /// Resolves addresses for up to [maxLookups] of the given stations that
  /// don't already have a readable one. Call this with an
  /// already distance-sorted list (fetchNearby already sorts by
  /// distanceKm) so the closest — most likely to actually be opened —
  /// stations get priority, since only a capped number are looked up
  /// live per call to keep the initial fetch from stalling on a long
  /// queue of 1-per-second requests.
  ///
  /// Anything beyond that cap, or that Nominatim couldn't resolve, falls
  /// back to "Near <the closest resolved neighbour>" if one exists
  /// within ~350m — same as the MyGeoMap version — so a cluster of
  /// nearby stations only needs one of them to succeed.
  ///
  /// Cached permanently (by rounded coordinate) so a given area only
  /// ever needs a live lookup once across the app's lifetime, not once
  /// per screen visit.
  static Future<Map<String, String>> resolveMissing(
    List<FuelStation> stations, {
    int maxLookups = 6,
  }) async {
    final cache = await _loadCache();
    final resolved = <String, String>{};
    final pending = <FuelStation>[];

    for (final station in stations.where((item) => !item.hasReadableAddress)) {
      final saved = cache[_coordinateKey(station)];
      if (saved != null && saved.isNotEmpty) {
        resolved[station.id] = saved;
      } else {
        pending.add(station);
      }
    }

    var changed = false;
    for (final station in pending.take(maxLookups)) {
      final address = await _throttledReverseGeocode(station);
      if (address == null) continue;
      resolved[station.id] = address;
      cache[_coordinateKey(station)] = address;
      changed = true;
    }

    for (final station in pending) {
      if (resolved.containsKey(station.id)) continue;
      String? nearestAddress;
      var nearestDistance = 0.35;
      for (final candidate in stations) {
        if (candidate.id == station.id) continue;
        final candidateAddress =
            candidate.hasReadableAddress ? candidate.address : resolved[candidate.id];
        if (candidateAddress == null) continue;
        final distance = LocationService.distanceKm(
          AppLatLng(station.latitude, station.longitude),
          AppLatLng(candidate.latitude, candidate.longitude),
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestAddress = candidateAddress;
        }
      }
      if (nearestAddress != null) {
        final readable = nearestAddress.startsWith('Near ') ? nearestAddress : 'Near $nearestAddress';
        resolved[station.id] = readable;
        cache[_coordinateKey(station)] = readable;
        changed = true;
      }
    }

    if (changed) await _saveCache(cache);
    return resolved;
  }

  /// On-demand single lookup for the detail screen — so a station that
  /// wasn't inside the capped [resolveMissing] batch (or that's opened
  /// well after that first fetch) still eventually gets a real address
  /// instead of being stuck on the placeholder message forever. Goes
  /// through the same app-wide throttle as everything else, so it's
  /// always safe to call regardless of what else is mid-lookup.
  static Future<String?> resolveOne(FuelStation station) async {
    if (station.hasReadableAddress) return station.address;
    final cache = await _loadCache();
    final cached = cache[_coordinateKey(station)];
    if (cached != null && cached.isNotEmpty) return cached;

    final address = await _throttledReverseGeocode(station);
    if (address != null) {
      cache[_coordinateKey(station)] = address;
      await _saveCache(cache);
    }
    return address;
  }

  static Future<String?> _throttledReverseGeocode(FuelStation station) {
    final result = _throttleChain.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final remaining = _minGapBetweenRequests - DateTime.now().difference(last);
        if (remaining > Duration.zero) await Future.delayed(remaining);
      }
      _lastRequestAt = DateTime.now();
      return _reverseGeocode(station);
    });
    // Keep the chain alive even if this particular lookup throws, so one
    // failure can't jam every lookup queued behind it.
    _throttleChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<String?> _reverseGeocode(FuelStation station) async {
    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'format': 'jsonv2',
        'lat': '${station.latitude}',
        'lon': '${station.longitude}',
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await http
          .get(uri, headers: const {'User-Agent': 'FuelGo/1.0 (nearby station finder)'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['error'] != null) return null;

      final addr = body['address'] as Map<String, dynamic>?;
      final parts = [
        [addr?['house_number'], addr?['road']].whereType<String>().join(' '),
        addr?['suburb'] ?? addr?['neighbourhood'],
        addr?['city'] ?? addr?['town'] ?? addr?['village'],
        addr?['state'],
        addr?['postcode'],
      ]
          .whereType<String>()
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .join(', ');

      final candidate = parts.isNotEmpty ? parts : (body['display_name'] as String?)?.trim();
      if (candidate == null || candidate.isEmpty) return null;

      // Nominatim can hand back the station itself (it's an OSM node
      // too) rather than a genuinely separate nearby address — skip that
      // case, same as MyGeoMapReverseGeocodingService does, so the
      // nearest-neighbour fallback gets a chance to find something real
      // instead of a "Near <its own name>" non-answer.
      final normalisedCandidate = candidate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normalisedName = station.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalisedCandidate == normalisedName) return null;

      return 'Near $candidate';
    } catch (error) {
      debugPrint('[OsmReverseGeocodingService] Lookup failed: $error');
      return null;
    }
  }

  static String _coordinateKey(FuelStation station) =>
      '${station.latitude.toStringAsFixed(5)},${station.longitude.toStringAsFixed(5)}';

  static Future<Map<String, String>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return _cache = {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return _cache = decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (error) {
      debugPrint('[OsmReverseGeocodingService] Cache read failed: $error');
      return _cache = {};
    }
  }

  static Future<void> _saveCache(Map<String, String> cache) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(cache));
    } catch (error) {
      debugPrint('[OsmReverseGeocodingService] Cache write failed: $error');
    }
  }
}
