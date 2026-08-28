import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'location_service.dart';
import 'mygeomap_fuel_service.dart';
import 'osm_fuel_service.dart';
import 'osm_ev_charger_service.dart';

class _CacheEntry<T> {
  final List<T> data;
  final AppLatLng center;
  final double radiusKm;
  final int limit;
  final DateTime fetchedAt;
  _CacheEntry(
      this.data, this.center, this.radiusKm, this.limit, this.fetchedAt);
}

/// Shared in-memory cache for fuel/EV data fetched from OpenStreetMap, so
/// re-opening the Home quick-access cards, the Fuel/EV list screens, or the
/// Smart Mobility Map doesn't hit the network again every single time.
///
/// A cached result is reused only when all of the following hold:
///  - it was fetched with the same radius/limit as the new request,
///  - the new center is within [maxDriftKm] of where it was fetched, and
///  - it's less than [ttl] old.
/// Otherwise it's treated as a miss and re-fetched (and the cache updated).
///
/// This is in-memory only, same as FavouritesService/VehiclePreferenceService
/// — it resets on app restart, which is the point of calling it "temporary".
class StationCacheService {
  StationCacheService._();
  static final StationCacheService instance = StationCacheService._();

  static const ttl = Duration(minutes: 5);
  static const maxDriftKm = 1.5;
  static const _fuelStorageKey = 'nearby_fuel_station_cache_v2';
  static const _diskMaxAge = Duration(days: 30);

  _CacheEntry<FuelStation>? _fuel;
  _CacheEntry<EVCharger>? _ev;
  Future<List<FuelStation>>? _fuelRequest;

  bool _isHit(_CacheEntry? e, AppLatLng loc, double radiusKm, int limit) {
    if (e == null) return false;
    if (e.radiusKm != radiusKm || e.limit != limit) return false;
    if (DateTime.now().difference(e.fetchedAt) > ttl) return false;
    if (LocationService.distanceKm(e.center, loc) > maxDriftKm) return false;
    return true;
  }

  bool _canFallback(
      _CacheEntry? entry, AppLatLng loc, double radiusKm, int limit) {
    if (entry == null) return false;
    return entry.radiusKm == radiusKm &&
        entry.limit == limit &&
        LocationService.distanceKm(entry.center, loc) <= maxDriftKm;
  }

  /// Fetches nearby fuel stations, serving from cache when possible.
  /// Pass `forceRefresh: true` (e.g. from a user-tapped refresh button) to
  /// skip the cache and always hit the network.
  Future<List<FuelStation>> fuel(
    AppLatLng loc, {
    double radiusKm = 15,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final saved = await _readFuelCache(loc, radiusKm, limit);
      if (saved != null) {
        _fuel = saved;
      }
    }
    return _requestFuel(loc, radiusKm, limit);
  }

  Future<List<FuelStation>> _requestFuel(
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    if (_fuelRequest != null) return _fuelRequest!;
    final request = _refreshFuel(loc, radiusKm, limit);
    _fuelRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_fuelRequest, request)) _fuelRequest = null;
    }
  }

  Future<List<FuelStation>> _refreshFuel(
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    final osmRequest = OsmFuelService.fetchNearby(
      loc,
      radiusKm: radiusKm,
      limit: limit,
    ).then(
      (data) => _FuelFetchResult(data),
      onError: (Object error) => _FuelFetchResult(const [], error: error),
    );
    Object? governmentError;
    try {
      final data = await MyGeoMapFuelService.fetchNearby(
        loc,
        radiusKm: radiusKm,
        limit: limit,
      );
      if (data.isNotEmpty) {
        final osmResult = await osmRequest.timeout(
          const Duration(seconds: 8),
          onTimeout: () => const _FuelFetchResult([]),
        );
        var enriched = _mergeOsmDetails(data, osmResult.data);
        if (_canFallback(_fuel, loc, radiusKm, limit)) {
          enriched = _mergeOsmDetails(enriched, _fuel!.data);
        }
        await _storeFuelCache(enriched, loc, radiusKm, limit);
        return enriched;
      }
    } catch (error) {
      governmentError = error;
      debugPrint('[StationCacheService] MyGeoMap failed: $error');
    }

    if (_canFallback(_fuel, loc, radiusKm, limit)) {
      return _fuel!.data;
    }

    try {
      final osmResult = await osmRequest;
      if (osmResult.error != null) throw osmResult.error!;
      await _storeFuelCache(osmResult.data, loc, radiusKm, limit);
      return osmResult.data;
    } catch (error) {
      debugPrint('[StationCacheService] OSM fallback failed: $error');
      if (_canFallback(_fuel, loc, radiusKm, limit)) return _fuel!.data;
      throw governmentError ?? error;
    }
  }

  List<FuelStation> _mergeOsmDetails(
    List<FuelStation> governmentStations,
    List<FuelStation> osmStations,
  ) {
    if (osmStations.isEmpty) return governmentStations;
    return governmentStations.map((station) {
      FuelStation? closest;
      var closestDistance = 0.2;
      final stationBrand = _normaliseBrand(station.brand ?? station.name);
      for (final candidate in osmStations) {
        if (_normaliseBrand(candidate.brand ?? candidate.name) !=
            stationBrand) {
          continue;
        }
        final distance = LocationService.distanceKm(
          AppLatLng(station.latitude, station.longitude),
          AppLatLng(candidate.latitude, candidate.longitude),
        );
        if (distance < closestDistance) {
          closestDistance = distance;
          closest = candidate;
        }
      }
      if (closest == null) return station;
      return FuelStation(
        id: station.id,
        name: station.name,
        brand: station.brand,
        address: station.address,
        latitude: station.latitude,
        longitude: station.longitude,
        distanceKm: station.distanceKm,
        open24Hours: station.open24Hours ?? closest.open24Hours,
        openingHoursRaw: station.openingHoursRaw ??
            (station.open24Hours == null ? closest.openingHoursRaw : null),
        fuelTypes: {...station.fuelTypes, ...closest.fuelTypes}.toList(),
        services: {...station.services, ...closest.services}.toList(),
        brandColor: station.brandColor,
        imageUrl: station.imageUrl ?? closest.imageUrl,
        website: station.website ?? closest.website,
      );
    }).toList(growable: false);
  }

  String _normaliseBrand(String value) {
    final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.contains('petronas')) return 'petronas';
    if (compact.contains('shell')) return 'shell';
    if (compact.contains('bhpetrol') || compact == 'bhp') return 'bhpetrol';
    if (compact.contains('petron')) return 'petron';
    if (compact.contains('caltex') || compact.contains('chevron')) {
      return 'caltex';
    }
    return compact;
  }

  Future<void> _storeFuelCache(
    List<FuelStation> data,
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    final now = DateTime.now();
    _fuel = _CacheEntry(data, loc, radiusKm, limit, now);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _fuelStorageKey,
        jsonEncode({
          'latitude': loc.lat,
          'longitude': loc.lng,
          'radiusKm': radiusKm,
          'limit': limit,
          'fetchedAt': now.toIso8601String(),
          'stations': data.map((station) => station.toJson()).toList(),
        }),
      );
    } catch (error) {
      debugPrint('[StationCacheService] Could not persist cache: $error');
    }
  }

  Future<_CacheEntry<FuelStation>?> _readFuelCache(
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_fuelStorageKey);
      if (raw == null) return null;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final center = AppLatLng(
        (saved['latitude'] as num).toDouble(),
        (saved['longitude'] as num).toDouble(),
      );
      final fetchedAt = DateTime.parse(saved['fetchedAt'] as String);
      if ((saved['radiusKm'] as num).toDouble() != radiusKm ||
          (saved['limit'] as num).toInt() != limit ||
          DateTime.now().difference(fetchedAt) > _diskMaxAge ||
          LocationService.distanceKm(center, loc) > maxDriftKm) {
        return null;
      }
      final stations = (saved['stations'] as List<dynamic>)
          .map((value) =>
              FuelStation.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList();
      return _CacheEntry(stations, center, radiusKm, limit, fetchedAt);
    } catch (error) {
      debugPrint('[StationCacheService] Ignored invalid saved cache: $error');
      return null;
    }
  }

  /// Fetches nearby EV chargers, serving from cache when possible. Same
  /// `forceRefresh` behaviour as [fuel].
  Future<List<EVCharger>> ev(
    AppLatLng loc, {
    double radiusKm = 15,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _isHit(_ev, loc, radiusKm, limit)) {
      return _ev!.data;
    }
    final data = await OsmEvChargerService.fetchNearby(loc,
        radiusKm: radiusKm, limit: limit);
    _ev = _CacheEntry(data, loc, radiusKm, limit, DateTime.now());
    return data;
  }

  /// Drops any cached data so the next fetch always goes to the network.
  void invalidate() {
    _fuel = null;
    _ev = null;
  }
}

class _FuelFetchResult {
  final List<FuelStation> data;
  final Object? error;

  const _FuelFetchResult(this.data, {this.error});
}
