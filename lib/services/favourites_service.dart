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
/// The full station/charger object is cached locally (SharedPreferences)
/// at the moment it's favourited, so the Favourites tab can show it
/// regardless of the user's current location or search radius — a
/// favourite shouldn't disappear just because it's no longer nearby.
///
/// The id sets are also synced to the signed-in account's Firestore
/// profile (favouriteFuelIds/favouriteEvIds), so *which* things are
/// favourited follows the account across devices — though the full
/// object details for a favourite added on a different device only
/// appear locally once it's been fetched nearby on this device too.
///
/// Call [hydrate] after reading the account's profile (see
/// AuthGate/LoginScreen) to load the saved id sets back in, and [reset]
/// on logout so the next account signed in on this device doesn't
/// briefly see the previous account's favourites.
class FavouritesService extends ChangeNotifier {
  FavouritesService._();
  static final FavouritesService instance = FavouritesService._();

  final Set<String> _fuelIds = {};
  final Set<String> _evIds = {};
  final Map<String, FuelStation> _fuelStations = {};
  final Map<String, EVCharger> _evChargers = {};
  static const _fuelStorageKey = 'favourite_fuel_stations_v1';
  static const _evStorageKey = 'favourite_ev_chargers_v1';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    for (final raw in prefs.getStringList(_fuelStorageKey) ?? const []) {
      try {
        final station = FuelStation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _fuelIds.add(station.id);
        _fuelStations[station.id] = station;
      } catch (e) {
        debugPrint('[FavouritesService] Ignored invalid saved station: $e');
      }
    }
    for (final raw in prefs.getStringList(_evStorageKey) ?? const []) {
      try {
        final charger = EVCharger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _evIds.add(charger.id);
        _evChargers[charger.id] = charger;
      } catch (e) {
        debugPrint('[FavouritesService] Ignored invalid saved charger: $e');
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

  void toggleEv(EVCharger charger) {
    if (_evIds.remove(charger.id)) {
      _evChargers.remove(charger.id);
    } else {
      _evIds.add(charger.id);
      _evChargers[charger.id] = charger;
    }
    _saveEvChargers();
    notifyListeners();
    _sync();
  }

  Future<void> _saveFuelStations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _fuelStorageKey,
      _fuelStations.values.map((station) => jsonEncode(station.toJson())).toList(),
    );
  }

  Future<void> _saveEvChargers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _evStorageKey,
      _evChargers.values.map((charger) => jsonEncode(charger.toJson())).toList(),
    );
  }

  Set<String> get fuelIds => _fuelIds;
  Set<String> get evIds => _evIds;
  List<FuelStation> get fuelStations => List.unmodifiable(_fuelStations.values);
  List<EVCharger> get evChargers => List.unmodifiable(_evChargers.values);

  /// Loads a previously saved set of favourite ids (e.g. from the
  /// account's Firestore profile) without re-triggering a write back to
  /// Firestore. Only replaces the id sets — locally-cached full
  /// station/charger objects (from [initialize]) are left as-is, since
  /// those come from this device's own fetch history, not the account.
  void hydrate({required Set<String> fuelIds, required Set<String> evIds}) {
    _fuelIds
      ..clear()
      ..addAll(fuelIds);
    _evIds
      ..clear()
      ..addAll(evIds);
    // Drop any locally-cached objects for ids that are no longer
    // favourited on the account (e.g. unfavourited from another device).
    _fuelStations.removeWhere((id, _) => !_fuelIds.contains(id));
    _evChargers.removeWhere((id, _) => !_evIds.contains(id));
    notifyListeners();
  }

  /// Clears local state, e.g. on logout, so it doesn't leak into the next
  /// account signed in on this device.
  void reset() {
    _fuelIds.clear();
    _evIds.clear();
    _fuelStations.clear();
    _evChargers.clear();
    notifyListeners();
  }

  // Fire-and-forget — favourites should feel instant locally; a failed
  // sync just means it'll be retried on the next toggle rather than
  // blocking the UI.
  void _sync() {
    AuthService.updateFavourites(fuelIds: _fuelIds, evIds: _evIds);
  }
}
