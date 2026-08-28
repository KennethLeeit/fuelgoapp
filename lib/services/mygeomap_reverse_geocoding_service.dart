import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'location_service.dart';

class MyGeoMapReverseGeocodingService {
  static const _endpoint = 'https://nav.mygeomap.gov.my/arcgis/rest/services/'
      'Geocode/Geocode/GeocodeServer/reverseGeocode';
  static const _storageKey = 'mygeomap_reverse_address_cache_v1';
  static const _batchSize = 8;

  static Map<String, String>? _cache;

  static Future<Map<String, String>> resolveMissing(
    List<FuelStation> stations,
  ) async {
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
    for (var start = 0; start < pending.length; start += _batchSize) {
      final end = (start + _batchSize).clamp(0, pending.length).toInt();
      final batch = pending.sublist(start, end);
      final results = await Future.wait(batch.map(_reverseGeocode));
      for (var index = 0; index < batch.length; index++) {
        final address = results[index];
        if (address == null) continue;
        final station = batch[index];
        resolved[station.id] = address;
        cache[_coordinateKey(station)] = address;
        changed = true;
      }
    }

    for (final station in pending) {
      if (resolved.containsKey(station.id)) continue;
      String? nearestAddress;
      var nearestDistance = 0.35;
      for (final candidate in stations) {
        if (candidate.id == station.id) continue;
        final candidateAddress = candidate.hasReadableAddress
            ? candidate.address
            : resolved[candidate.id];
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
        final readable = nearestAddress.startsWith('Near ')
            ? nearestAddress
            : 'Near $nearestAddress';
        resolved[station.id] = readable;
        cache[_coordinateKey(station)] = readable;
        changed = true;
      }
    }

    if (changed) await _saveCache(cache);
    return resolved;
  }

  static Future<String?> _reverseGeocode(FuelStation station) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.parse(_endpoint).replace(queryParameters: {
          'f': 'json',
          'location': '${station.longitude},${station.latitude}',
          'distance': '300',
          'outSR': '4326',
          'featureTypes': 'StreetAddress',
        });
        final response =
            await http.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) continue;
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['error'] != null) continue;
        final address = body['address'] as Map<String, dynamic>?;
        final match = address?['Match_addr']?.toString().trim();
        if (match == null || match.isEmpty) continue;
        final normalisedMatch = match.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );
        final normalisedName = station.name.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            );
        if (normalisedMatch == normalisedName) continue;
        return 'Near $match';
      } catch (error) {
        debugPrint(
          '[MyGeoMapReverseGeocodingService] Lookup attempt ${attempt + 1} failed: $error',
        );
      }
    }
    return null;
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
      return _cache = decoded.map(
        (key, value) => MapEntry(key, value.toString()),
      );
    } catch (error) {
      debugPrint('[MyGeoMapReverseGeocodingService] Cache read failed: $error');
      return _cache = {};
    }
  }

  static Future<void> _saveCache(Map<String, String> cache) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(cache));
    } catch (error) {
      debugPrint(
          '[MyGeoMapReverseGeocodingService] Cache write failed: $error');
    }
  }
}
