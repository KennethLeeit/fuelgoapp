import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'location_service.dart';

class GeocodeTarget {
  final String id;
  final double latitude;
  final double longitude;
  final String name;
  final bool hasReadableAddress;
  final String? currentAddress;

  const GeocodeTarget({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.hasReadableAddress,
    this.currentAddress,
  });
}

class ReverseGeocodingService {
  static const _endpoint = 'https://nominatim.openstreetmap.org/reverse';
  static const _storageKey = 'osm_reverse_address_cache_v1';
  static const _minGapBetweenRequests = Duration(milliseconds: 1100);

  static Map<String, String>? _cache;

  static Future<void> _throttleChain = Future.value();
  static DateTime? _lastRequestAt;

  static Future<Map<String, String>> resolveMissing(
    List<GeocodeTarget> targets, {
    int maxLookups = 6,
  }) async {
    final cache = await _loadCache();
    final resolved = <String, String>{};
    final pending = <GeocodeTarget>[];

    for (final target in targets.where((item) => !item.hasReadableAddress)) {
      final saved = cache[_coordinateKey(target)];
      if (saved != null && saved.isNotEmpty) {
        resolved[target.id] = saved;
      } else {
        pending.add(target);
      }
    }

    var changed = false;
    for (final target in pending.take(maxLookups)) {
      final address = await _throttledReverseGeocode(target);
      if (address == null) continue;
      resolved[target.id] = address;
      cache[_coordinateKey(target)] = address;
      changed = true;
    }

    for (final target in pending) {
      if (resolved.containsKey(target.id)) continue;
      String? nearestAddress;
      var nearestDistance = 0.35;
      for (final candidate in targets) {
        if (candidate.id == target.id) continue;
        final candidateAddress = candidate.hasReadableAddress
            ? candidate.currentAddress
            : resolved[candidate.id];
        if (candidateAddress == null) continue;
        final distance = LocationService.distanceKm(
          AppLatLng(target.latitude, target.longitude),
          AppLatLng(candidate.latitude, candidate.longitude),
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestAddress = candidateAddress;
        }
      }
      if (nearestAddress != null) {
        final readable = nearestAddress.startsWith('Near ')
            ? nearestAddress
            : 'Near $nearestAddress';
        resolved[target.id] = readable;
        cache[_coordinateKey(target)] = readable;
        changed = true;
      }
    }

    if (changed) await _saveCache(cache);
    return resolved;
  }

  static Future<String?> resolveOne(GeocodeTarget target) async {
    if (target.hasReadableAddress) return target.currentAddress;
    final cache = await _loadCache();
    final cached = cache[_coordinateKey(target)];
    if (cached != null && cached.isNotEmpty) return cached;

    final address = await _throttledReverseGeocode(target);
    if (address != null) {
      cache[_coordinateKey(target)] = address;
      await _saveCache(cache);
    }
    return address;
  }

  static Future<String?> _throttledReverseGeocode(GeocodeTarget target) {
    final result = _throttleChain.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final remaining =
            _minGapBetweenRequests - DateTime.now().difference(last);
        if (remaining > Duration.zero) await Future.delayed(remaining);
      }
      _lastRequestAt = DateTime.now();
      return _reverseGeocode(target);
    });

    _throttleChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<String?> _reverseGeocode(GeocodeTarget target) async {
    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'format': 'jsonv2',
        'lat': '${target.latitude}',
        'lon': '${target.longitude}',
        'zoom': '18',
        'addressdetails': '1',
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'FuelGo/1.0 (nearby station finder)'
      }).timeout(const Duration(seconds: 8));
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

      final candidate =
          parts.isNotEmpty ? parts : (body['display_name'] as String?)?.trim();
      if (candidate == null || candidate.isEmpty) return null;

      final normalisedCandidate =
          candidate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final normalisedName =
          target.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalisedCandidate == normalisedName) return null;

      return 'Near $candidate';
    } catch (error) {
      debugPrint('[ReverseGeocodingService] Lookup failed: $error');
      return null;
    }
  }

  static String _coordinateKey(GeocodeTarget target) =>
      '${target.latitude.toStringAsFixed(5)},${target.longitude.toStringAsFixed(5)}';

  static Future<Map<String, String>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return _cache = {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return _cache =
          decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (error) {
      debugPrint('[ReverseGeocodingService] Cache read failed: $error');
      return _cache = {};
    }
  }

  static Future<void> _saveCache(Map<String, String> cache) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(cache));
    } catch (error) {
      debugPrint('[ReverseGeocodingService] Cache write failed: $error');
    }
  }
}
