import 'package:flutter/foundation.dart';

enum VehicleMode { fuelOnly, evOnly, both }

/// Tracks the user's vehicle preference (set on the Profile screen) and
/// exposes it app-wide so screens can show/hide fuel vs. EV features
/// accordingly. In-memory only (resets on app restart) — same pattern as
/// FavouritesService; swap in shared_preferences here if you want it to
/// persist.
class VehiclePreferenceService extends ChangeNotifier {
  VehiclePreferenceService._();
  static final VehiclePreferenceService instance = VehiclePreferenceService._();

  bool _drivesFuel = true;
  bool _drivesEV = true;

  bool get drivesFuel => _drivesFuel;
  bool get drivesEV => _drivesEV;

  /// If exactly one is selected, that's the locked mode. If both are
  /// selected, or neither is (nothing chosen yet), show everything — an
  /// empty selection isn't treated as "show nothing".
  VehicleMode get mode {
    if (_drivesFuel && !_drivesEV) return VehicleMode.fuelOnly;
    if (_drivesEV && !_drivesFuel) return VehicleMode.evOnly;
    return VehicleMode.both;
  }

  bool get showFuel => mode != VehicleMode.evOnly;
  bool get showEV => mode != VehicleMode.fuelOnly;
  bool get isLocked => mode != VehicleMode.both;

  void setDrivesFuel(bool value) {
    _drivesFuel = value;
    notifyListeners();
  }

  void setDrivesEV(bool value) {
    _drivesEV = value;
    notifyListeners();
  }

  /// Sets both flags at once from a saved account record (e.g. Firestore)
  /// without needing two separate notifications.
  void hydrate({required bool drivesFuel, required bool drivesEV}) {
    _drivesFuel = drivesFuel;
    _drivesEV = drivesEV;
    notifyListeners();
  }

  /// Resets to the default (both) on logout, so the next account signed
  /// in on this device doesn't briefly see the previous account's
  /// preference before its own profile is hydrated.
  void reset() {
    _drivesFuel = true;
    _drivesEV = true;
    notifyListeners();
  }
}
