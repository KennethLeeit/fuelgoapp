import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Tracks favourited fuel stations / EV chargers by their stable API id.
/// Needed because station/charger data is now fetched live each time
/// (instead of a fixed mock list), so we can't just mutate an object's
/// `isFavourite` field — the same place needs to be recognized as
/// favourited across separate fetches.
///
/// Local state lives in memory for instant UI updates, but every toggle is
/// also synced to the signed-in account's Firestore profile
/// (favouriteFuelIds/favouriteEvIds), so favourites persist across app
/// restarts and devices instead of resetting each session. Call [hydrate]
/// after reading the account's profile (see AuthGate/LoginScreen) to load
/// them back in, and [reset] on logout so the next account signed in on
/// this device doesn't briefly see the previous account's favourites.
class FavouritesService extends ChangeNotifier {
  FavouritesService._();
  static final FavouritesService instance = FavouritesService._();

  final Set<String> _fuelIds = {};
  final Set<String> _evIds = {};
  final Map<String, FuelStation> _fuelStations = {};
  static const _fuelStorageKey = 'favourite_fuel_stations_v1';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    for (final raw in prefs.getStringList(_fuelStorageKey) ?? const []) {
      try {
        final station =
            FuelStation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _fuelIds.add(station.id);
        _fuelStations[station.id] = station;
      } catch (e) {
        debugPrint('[FavouritesService] Ignored invalid saved station: $e');
      }
    }
  }

  bool isFuelFavourite(String id) => _fuelIds.contains(id);
  bool isEvFavourite(String id) => _evIds.contains(id);

  void toggleFuel(FuelStation station) {
    if (_fuelIds.remove(station.id)) {
      _fuelStations.remove(station.id);
    } else {
      _fuelIds.add(station.id);
      _fuelStations[station.id] = station;
    }
    _saveFuelStations();
    notifyListeners();
    _sync();
  }

  Future<void> _saveFuelStations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _fuelStorageKey,
      _fuelStations.values
          .map((station) => jsonEncode(station.toJson()))
          .toList(),
    );
  }

  void toggleEv(String id) {
    if (!_evIds.remove(id)) _evIds.add(id);
    notifyListeners();
    _sync();
  }

  Set<String> get fuelIds => _fuelIds;
  Set<String> get evIds => _evIds;
  List<FuelStation> get fuelStations => List.unmodifiable(_fuelStations.values);

  /// Loads a previously saved set of favourites (e.g. from the account's
  /// Firestore profile) without re-triggering a write back to Firestore.
  void hydrate({required Set<String> fuelIds, required Set<String> evIds}) {
    _fuelIds
      ..clear()
      ..addAll(fuelIds);
    _evIds
      ..clear()
      ..addAll(evIds);
    notifyListeners();
  }

  /// Clears local state, e.g. on logout, so it doesn't leak into the next
  /// account signed in on this device.
  void reset() {
    _fuelIds.clear();
    _evIds.clear();
    notifyListeners();
  }

  // Fire-and-forget — favourites should feel instant locally; a failed
  // sync just means it'll be retried on the next toggle rather than
  // blocking the UI.
  void _sync() {
    AuthService.updateFavourites(fuelIds: _fuelIds, evIds: _evIds);
  }
}
