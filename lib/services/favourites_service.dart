import 'package:flutter/foundation.dart';

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

  bool isFuelFavourite(String id) => _fuelIds.contains(id);
  bool isEvFavourite(String id) => _evIds.contains(id);

  void toggleFuel(String id) {
    if (!_fuelIds.remove(id)) _fuelIds.add(id);
    notifyListeners();
  }

  void toggleEv(String id) {
    if (!_evIds.remove(id)) _evIds.add(id);
    notifyListeners();
  }

  Set<String> get fuelIds => _fuelIds;
  Set<String> get evIds => _evIds;
}
