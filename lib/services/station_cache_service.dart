import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'location_service.dart';
import 'mygeomap_fuel_service.dart';
import 'osm_fuel_service.dart';
import 'osm_ev_charger_service.dart';
import 'open_charge_map_service.dart';

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
  static const _fuelStorageKey = 'nearby_fuel_station_cache_v3';
  static const _evStorageKey = 'nearby_ev_charger_cache_v3';
  static const _diskMaxAge = Duration(days: 30);

  _CacheEntry<FuelStation>? _fuel;
  _CacheEntry<EVCharger>? _ev;
  Future<List<FuelStation>>? _fuelRequest;
  AppLatLng? _fuelRequestCenter;
  double? _fuelRequestRadiusKm;
  int? _fuelRequestLimit;
  Future<List<EVCharger>>? _evRequest;
  AppLatLng? _evRequestCenter;
  double? _evRequestRadiusKm;
  int? _evRequestLimit;

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

  // In-flight dedup used to key only on type (one fuel request, one EV
  // request). A second caller for a *different* location would join the
  // wrong future, and the two callers' completion tracking would get
  // tangled. Only reuse a request when it's for the same area.
  bool _isSameInFlight(
    AppLatLng loc,
    double radiusKm,
    int limit,
    AppLatLng? center,
    double? requestRadiusKm,
    int? requestLimit,
  ) {
    if (center == null || requestRadiusKm == null || requestLimit == null) {
      return false;
    }
    return requestRadiusKm == radiusKm &&
        requestLimit == limit &&
        LocationService.distanceKm(center, loc) <= maxDriftKm;
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
    if (!forceRefresh && _isHit(_fuel, loc, radiusKm, limit)) {
      return _fuel!.data;
    }
    return _requestFuel(loc, radiusKm, limit, forceRefresh: forceRefresh);
  }

  Future<List<FuelStation>> _requestFuel(
    AppLatLng loc,
    double radiusKm,
    int limit, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _fuelRequest != null &&
        _isSameInFlight(loc, radiusKm, limit, _fuelRequestCenter,
            _fuelRequestRadiusKm, _fuelRequestLimit)) {
      return _fuelRequest!;
    }
    final request = _refreshFuel(loc, radiusKm, limit);
    _fuelRequest = request;
    _fuelRequestCenter = loc;
    _fuelRequestRadiusKm = radiusKm;
    _fuelRequestLimit = limit;
    try {
      return await request;
    } finally {
      if (identical(_fuelRequest, request)) {
        _fuelRequest = null;
        _fuelRequestCenter = null;
        _fuelRequestRadiusKm = null;
        _fuelRequestLimit = null;
      }
    }
  }

  Future<List<FuelStation>> _refreshFuel(
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    Object? governmentError;
    try {
      final data = await MyGeoMapFuelService.fetchNearby(
        loc,
        radiusKm: radiusKm,
        limit: limit,
      );
      if (data.isNotEmpty) {
        // Show government data immediately — it already has name, brand,
        // address, and location, which is everything the map/list need
        // to render markers. OSM enrichment (opening hours, amenities)
        // used to be awaited here before returning anything at all, which
        // meant a slow/flaky Overpass response held up the whole screen
        // even though the station data itself was already sitting there
        // ready to show. It's now applied in the background instead and
        // only benefits the *next* fetch (cache gets refreshed quietly).
        await _storeFuelCache(data, loc, radiusKm, limit);
        unawaited(_enrichWithOsmInBackground(data, loc, radiusKm, limit));
        return data;
      }
    } catch (error) {
      governmentError = error;
      debugPrint('[StationCacheService] MyGeoMap failed: $error');
    }

    if (_canFallback(_fuel, loc, radiusKm, limit)) {
      return _fuel!.data;
    }

    // No government data at all — OSM is the only source here, so this
    // path does have to wait for it.
    try {
      final osmStations = await OsmFuelService.fetchNearby(loc,
          radiusKm: radiusKm, limit: limit);
      await _storeFuelCache(osmStations, loc, radiusKm, limit);
      return osmStations;
    } catch (error) {
      debugPrint('[StationCacheService] OSM fallback failed: $error');
      if (_canFallback(_fuel, loc, radiusKm, limit)) return _fuel!.data;
      throw governmentError ?? error;
    }
  }

  // Fetches OSM details and merges them into the already-returned
  // government station list, then quietly refreshes the cache with the
  // enriched version — so a *future* fetch benefits without the current
  // one having had to wait for it.
  Future<void> _enrichWithOsmInBackground(
    List<FuelStation> governmentStations,
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    try {
      final osmStations = await OsmFuelService.fetchNearby(loc,
          radiusKm: radiusKm, limit: limit);
      if (osmStations.isEmpty) return;
      // Only update if nothing newer (a different location, a
      // force-refresh) has already replaced this entry in the meantime.
      if (_fuel == null || !identical(_fuel!.data, governmentStations)) return;
      final enriched = _mergeOsmDetails(governmentStations, osmStations);
      await _storeFuelCache(enriched, loc, radiusKm, limit);
    } catch (error) {
      debugPrint(
          '[StationCacheService] Background OSM enrichment failed: $error');
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
  /// `forceRefresh` behaviour as [fuel], including surviving an app
  /// restart via the same on-disk cache. OSM is used directly when no
  /// Open Charge Map key is configured; otherwise OCM remains primary and
  /// OSM is its fallback.
  Future<List<EVCharger>> ev(
    AppLatLng loc, {
    double radiusKm = 15,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final saved = await _readEvCache(loc, radiusKm, limit);
      if (saved != null) {
        _ev = saved;
      }
    }
    if (!forceRefresh && _isHit(_ev, loc, radiusKm, limit)) {
      return _ev!.data;
    }
    return _requestEv(loc, radiusKm, limit, forceRefresh: forceRefresh);
  }

  Future<List<EVCharger>> _requestEv(
    AppLatLng loc,
    double radiusKm,
    int limit, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _evRequest != null &&
        _isSameInFlight(loc, radiusKm, limit, _evRequestCenter,
            _evRequestRadiusKm, _evRequestLimit)) {
      return _evRequest!;
    }
    final request = _refreshEv(loc, radiusKm, limit);
    _evRequest = request;
    _evRequestCenter = loc;
    _evRequestRadiusKm = radiusKm;
    _evRequestLimit = limit;
    try {
      return await request;
    } finally {
      if (identical(_evRequest, request)) {
        _evRequest = null;
        _evRequestCenter = null;
        _evRequestRadiusKm = null;
        _evRequestLimit = null;
      }
    }
  }

  Future<List<EVCharger>> _refreshEv(
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    if (OpenChargeMapService.apiKey == null) {
      try {
        final osmData = await OsmEvChargerService.fetchNearby(
          loc,
          radiusKm: radiusKm,
          limit: limit,
        );
        await _storeEvCache(osmData, loc, radiusKm, limit);
        return osmData;
      } catch (error) {
        debugPrint('[StationCacheService] OSM EV fetch failed: $error');
        if (_canFallback(_ev, loc, radiusKm, limit)) return _ev!.data;
        rethrow;
      }
    }
    Object? ocmError;
    try {
      final data = await OpenChargeMapService.fetchNearby(loc,
          radiusKm: radiusKm, limit: limit);
      if (data.isNotEmpty) {
        await _storeEvCache(data, loc, radiusKm, limit);
        return data;
      }
    } catch (error) {
      ocmError = error;
      debugPrint('[StationCacheService] Open Charge Map failed: $error');
    }

    if (_canFallback(_ev, loc, radiusKm, limit)) {
      return _ev!.data;
    }

    // OCM returned nothing (or failed) for this area — fall back to OSM.
    try {
      final osmData = await OsmEvChargerService.fetchNearby(loc,
          radiusKm: radiusKm, limit: limit);
      await _storeEvCache(osmData, loc, radiusKm, limit);
      return osmData;
    } catch (error) {
      debugPrint('[StationCacheService] OSM EV fallback failed: $error');
      if (_canFallback(_ev, loc, radiusKm, limit)) return _ev!.data;
      throw ocmError ?? error;
    }
  }

  Future<void> _storeEvCache(
    List<EVCharger> data,
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    final now = DateTime.now();
    _ev = _CacheEntry(data, loc, radiusKm, limit, now);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _evStorageKey,
        jsonEncode({
          'latitude': loc.lat,
          'longitude': loc.lng,
          'radiusKm': radiusKm,
          'limit': limit,
          'fetchedAt': now.toIso8601String(),
          'chargers': data.map((charger) => charger.toJson()).toList(),
        }),
      );
    } catch (error) {
      debugPrint('[StationCacheService] Could not persist EV cache: $error');
    }
  }

  Future<_CacheEntry<EVCharger>?> _readEvCache(
    AppLatLng loc,
    double radiusKm,
    int limit,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_evStorageKey);
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
      final chargers = (saved['chargers'] as List<dynamic>)
          .map((value) =>
              EVCharger.fromJson(Map<String, dynamic>.from(value as Map)))
          .toList();
      return _CacheEntry(chargers, center, radiusKm, limit, fetchedAt);
    } catch (error) {
      debugPrint(
          '[StationCacheService] Ignored invalid saved EV cache: $error');
      return null;
    }
  }

  /// Drops any cached data so the next fetch always goes to the network.
  void invalidate() {
    _fuel = null;
    _ev = null;
  }

  /// Warms the cache for the device's current location — same
  /// radius/limit the Fuel/EV list screens and the map use. Meant to be
  /// called as early as possible, even before the user has logged in
  /// (see LoginScreen), so that by the time they actually reach the main
  /// app the data's often already there instead of showing a loading
  /// spinner. Fire-and-forget: a failure here (e.g. location permission
  /// not granted yet) is silently retried by whichever screen the user
  /// opens next, which does its own error handling.
  Future<void> prefetchNearby() async {
    try {
      final loc = await LocationService.getCurrentLocation();
      unawaited(fuel(loc, radiusKm: 12, limit: 40));
      unawaited(ev(loc, radiusKm: 12, limit: 40));
    } catch (_) {
      // Best-effort warm-up only.
    }
  }
}
