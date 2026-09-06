import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'app_messenger.dart';
import 'location_service.dart';
import 'mygeomap_fuel_service.dart';
import 'osm_fuel_service.dart';
import 'osm_ev_charger_service.dart';
import 'open_charge_map_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class FavouriteSyncError {
  final String message;
  final DateTime at;
  FavouriteSyncError(this.message) : at = DateTime.now();
}

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
        final station =
            FuelStation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        _fuelIds.add(station.id);
        _fuelStations[station.id] = station;
      } catch (e) {
        debugPrint('[FavouritesService] Ignored invalid saved station: $e');
      }
    }
    for (final raw in prefs.getStringList(_evStorageKey) ?? const []) {
      try {
        final charger =
            EVCharger.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
      _fuelStations.values
          .map((station) => jsonEncode(station.toJson()))
          .toList(),
    );
  }

  Future<void> _saveEvChargers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _evStorageKey,
      _evChargers.values
          .map((charger) => jsonEncode(charger.toJson()))
          .toList(),
    );
  }

  Set<String> get fuelIds => _fuelIds;
  Set<String> get evIds => _evIds;
  List<FuelStation> get fuelStations => List.unmodifiable(_fuelStations.values);
  List<EVCharger> get evChargers => List.unmodifiable(_evChargers.values);

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

    if (hasLocalOnlyFuel || hasLocalOnlyEv) _sync();
  }

  Future<void> reconcileMissing() async {
    final missingFuel =
        _fuelIds.where((id) => !_fuelStations.containsKey(id)).toList();
    final missingEv =
        _evIds.where((id) => !_evChargers.containsKey(id)).toList();
    if (missingFuel.isEmpty && missingEv.isEmpty) return;

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
          final stations = await MyGeoMapFuelService.fetchByObjectIds(
              mygeomapObjectIds,
              reference: loc);
          for (final s in stations) {
            if (missingFuel.contains(s.id)) {
              _fuelStations[s.id] = s;
              changed = true;
            }
          }
        } catch (e) {
          debugPrint(
              '[FavouritesService] Could not fetch MyGeoMap favourites: $e');
        }
      }
      if (osmIds.isNotEmpty) {
        try {
          final stations =
              await OsmFuelService.fetchByIds(osmIds, reference: loc);
          for (final s in stations) {
            if (missingFuel.contains(s.id)) {
              _fuelStations[s.id] = s;
              changed = true;
            }
          }
        } catch (e) {
          debugPrint(
              '[FavouritesService] Could not fetch OSM fuel favourites: $e');
        }
      }
    }

    if (missingEv.isNotEmpty) {
      final ocmIds = <String>[];
      final osmIds = <String>[];
      for (final id in missingEv) {
        if (id.startsWith('ocm/')) {
          ocmIds.add(id.substring('ocm/'.length));
        } else {
          osmIds.add(id);
        }
      }
      if (ocmIds.isNotEmpty) {
        if (OpenChargeMapService.apiKey != null) {
          try {
            final chargers =
                await OpenChargeMapService.fetchByIds(ocmIds, reference: loc);
            for (final c in chargers) {
              if (missingEv.contains(c.id)) {
                _evChargers[c.id] = c;
                changed = true;
              }
            }
          } catch (e) {
            debugPrint(
                '[FavouritesService] Could not fetch Open Charge Map favourites: $e');
          }
        }
      }
      if (osmIds.isNotEmpty) {
        try {
          final chargers =
              await OsmEvChargerService.fetchByIds(osmIds, reference: loc);
          for (final c in chargers) {
            if (missingEv.contains(c.id)) {
              _evChargers[c.id] = c;
              changed = true;
            }
          }
        } catch (e) {
          debugPrint(
              '[FavouritesService] Could not fetch OSM EV charger favourites: $e');
        }
      }
    }

    if (changed) {
      await _saveFuelStations();
      await _saveEvChargers();
      notifyListeners();
    }
  }

  int get missingFuelCount =>
      _fuelIds.where((id) => !_fuelStations.containsKey(id)).length;
  int get missingEvCount =>
      _evIds.where((id) => !_evChargers.containsKey(id)).length;

  bool get hasUnresolvableOcmFavourites =>
      OpenChargeMapService.apiKey == null &&
      _evIds.any((id) => id.startsWith('ocm/') && !_evChargers.containsKey(id));

  void reset() {
    _fuelIds.clear();
    _evIds.clear();
    _fuelStations.clear();
    _evChargers.clear();
    notifyListeners();
  }

  void _sync() async {
    final error =
        await AuthService.updateFavourites(fuelIds: _fuelIds, evIds: _evIds);
    if (error != null) {
      AppMessenger.showError('Could not save favourites: $error');
    }
  }
}
