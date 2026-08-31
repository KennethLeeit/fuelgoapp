import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'app_messenger.dart';
import 'location_service.dart';
import 'mygeomap_fuel_service.dart';
import 'osm_fuel_service.dart';
import 'osm_ev_charger_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// A favourites sync failure, carrying its own timestamp so listeners can
/// tell a fresh failure apart from the same message being read again.
class FavouriteSyncError {
  final String message;
  final DateTime at;
  FavouriteSyncError(this.message) : at = DateTime.now();
}

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

  /// Merges in a previously saved set of favourite ids (e.g. from the
  /// account's Firestore profile). This is additive/non-destructive on
  /// purpose: a favourite that exists locally but isn't in [fuelIds]/
  /// [evIds] is kept (and re-synced to Firestore below) rather than
  /// deleted — deleting it here would be indistinguishable from "this
  /// device's favourite just hasn't synced to the account yet" (e.g. an
  /// earlier sync attempt failed), and silently losing a saved favourite
  /// is worse than occasionally keeping one that was actually removed on
  /// another device. Kicks off [reconcileMissing] afterwards so any
  /// favourite id from the account that doesn't have a locally-cached
  /// object yet gets its details filled in automatically.
  void hydrate({required Set<String> fuelIds, required Set<String> evIds}) {
    final mergedFuel = {..._fuelIds, ...fuelIds};
    final mergedEv = {..._evIds, ...evIds};
    final hasLocalOnlyFuel = mergedFuel.length > fuelIds.length;
    final hasLocalOnlyEv = mergedEv.length > evIds.length;

    _fuelIds
      ..clear()
      ..addAll(mergedFuel);
    _evIds
      ..clear()
      ..addAll(mergedEv);
    notifyListeners();
    reconcileMissing();

    // If this device knew about a favourite the account didn't, push it
    // back up so it isn't orphaned going forward (e.g. because an earlier
    // sync attempt silently failed before this fix).
    if (hasLocalOnlyFuel || hasLocalOnlyEv) _sync();
  }

  /// Best-effort reconciliation: if a favourited id doesn't have a full
  /// station/charger object cached locally yet (e.g. it was favourited on
  /// a different device, or synced from Firestore before local caching
  /// existed), fetch it directly by its exact id — no location or radius
  /// involved, so a favourite the user saved on the other side of the
  /// country still resolves. [missingFuelCount]/[missingEvCount] reflect
  /// anything that still couldn't be found (e.g. removed from the source
  /// data, or a network failure) so the UI can hint at that.
  Future<void> reconcileMissing() async {
    final missingFuel = _fuelIds.where((id) => !_fuelStations.containsKey(id)).toList();
    final missingEv = _evIds.where((id) => !_evChargers.containsKey(id)).toList();
    if (missingFuel.isEmpty && missingEv.isEmpty) return;

    // Only used to set a "distance from you" label on the results —
    // resolving favourites by id doesn't depend on location, so this is
    // allowed to fail (e.g. permission denied) without blocking anything.
    AppLatLng? loc;
    try {
      loc = await LocationService.getCurrentLocation();
    } catch (_) {
      loc = null;
    }

    var changed = false;

    if (missingFuel.isNotEmpty) {
      final mygeomapObjectIds = <String>[];
      final osmIds = <String>[];
      for (final id in missingFuel) {
        if (id.startsWith('mygeomap/')) {
          mygeomapObjectIds.add(id.substring('mygeomap/'.length));
        } else {
          osmIds.add(id);
        }
      }
      if (mygeomapObjectIds.isNotEmpty) {
        try {
          final stations = await MyGeoMapFuelService.fetchByObjectIds(mygeomapObjectIds, reference: loc);
          for (final s in stations) {
            if (missingFuel.contains(s.id)) {
              _fuelStations[s.id] = s;
              changed = true;
            }
          }
        } catch (e) {
          debugPrint('[FavouritesService] Could not fetch MyGeoMap favourites: $e');
        }
      }
      if (osmIds.isNotEmpty) {
        try {
          final stations = await OsmFuelService.fetchByIds(osmIds, reference: loc);
          for (final s in stations) {
            if (missingFuel.contains(s.id)) {
              _fuelStations[s.id] = s;
              changed = true;
            }
          }
        } catch (e) {
          debugPrint('[FavouritesService] Could not fetch OSM fuel favourites: $e');
        }
      }
    }

    if (missingEv.isNotEmpty) {
      try {
        final chargers = await OsmEvChargerService.fetchByIds(missingEv, reference: loc);
        for (final c in chargers) {
          if (missingEv.contains(c.id)) {
            _evChargers[c.id] = c;
            changed = true;
          }
        }
      } catch (e) {
        debugPrint('[FavouritesService] Could not fetch EV charger favourites: $e');
      }
    }

    if (changed) {
      await _saveFuelStations();
      await _saveEvChargers();
      notifyListeners();
    }
  }

  /// Favourited on the account but couldn't be resolved yet — either the
  /// lookup hasn't run yet, it failed (e.g. no network), or the place has
  /// been removed from the source data. Lets the Favourites screen show a
  /// helpful hint instead of just silently showing fewer items.
  int get missingFuelCount => _fuelIds.where((id) => !_fuelStations.containsKey(id)).length;
  int get missingEvCount => _evIds.where((id) => !_evChargers.containsKey(id)).length;

  /// Clears local state, e.g. on logout, so it doesn't leak into the next
  /// account signed in on this device.
  void reset() {
    _fuelIds.clear();
    _evIds.clear();
    _fuelStations.clear();
    _evChargers.clear();
    notifyListeners();
  }

  // Fire-and-forget from the caller's point of view (favourites should
  // feel instant locally), but the result IS checked here — a failure
  // shows a global SnackBar with the real reason instead of silently
  // doing nothing, which is what made this look like it "didn't save".
  void _sync() async {
    final error = await AuthService.updateFavourites(fuelIds: _fuelIds, evIds: _evIds);
    if (error != null) {
      AppMessenger.showError('Could not save favourites: $error');
    }
  }
}
