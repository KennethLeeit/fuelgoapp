import '../models/models.dart';
import 'location_service.dart';
import 'osm_fuel_service.dart';
import 'osm_ev_charger_service.dart';

class _CacheEntry<T> {
  final List<T> data;
  final AppLatLng center;
  final double radiusKm;
  final int limit;
  final DateTime fetchedAt;
  _CacheEntry(this.data, this.center, this.radiusKm, this.limit, this.fetchedAt);
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

  _CacheEntry<FuelStation>? _fuel;
  _CacheEntry<EVCharger>? _ev;

  bool _isHit(_CacheEntry? e, AppLatLng loc, double radiusKm, int limit) {
    if (e == null) return false;
    if (e.radiusKm != radiusKm || e.limit != limit) return false;
    if (DateTime.now().difference(e.fetchedAt) > ttl) return false;
    if (LocationService.distanceKm(e.center, loc) > maxDriftKm) return false;
    return true;
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
    if (!forceRefresh && _isHit(_fuel, loc, radiusKm, limit)) {
      return _fuel!.data;
    }
    final data = await OsmFuelService.fetchNearby(loc, radiusKm: radiusKm, limit: limit);
    _fuel = _CacheEntry(data, loc, radiusKm, limit, DateTime.now());
    return data;
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
    final data = await OsmEvChargerService.fetchNearby(loc, radiusKm: radiusKm, limit: limit);
    _ev = _CacheEntry(data, loc, radiusKm, limit, DateTime.now());
    return data;
  }

  /// Drops any cached data so the next fetch always goes to the network.
  void invalidate() {
    _fuel = null;
    _ev = null;
  }
}
