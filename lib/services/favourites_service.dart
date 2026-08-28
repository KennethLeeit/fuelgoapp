import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Tracks favourited fuel stations / EV chargers by their stable API id.
/// Needed because station/charger data is now fetched live each time
/// (instead of a fixed mock list), so we can't just mutate an object's
/// `isFavourite` field — the same place needs to be recognized as
/// favourited across separate fetches.
///
/// This is in-memory only (resets on app restart). Swap in
/// shared_preferences or a backend call here if you want it to persist.
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
  }

  Set<String> get fuelIds => _fuelIds;
  Set<String> get evIds => _evIds;
  List<FuelStation> get fuelStations => List.unmodifiable(_fuelStations.values);
}
