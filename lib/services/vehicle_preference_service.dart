import 'package:flutter/foundation.dart';

enum VehicleMode { fuelOnly, evOnly, both }

class VehiclePreferenceService extends ChangeNotifier {
  VehiclePreferenceService._();
  static final VehiclePreferenceService instance = VehiclePreferenceService._();

  bool _drivesFuel = true;
  bool _drivesEV = true;

  bool get drivesFuel => _drivesFuel;
  bool get drivesEV => _drivesEV;

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

  void hydrate({required bool drivesFuel, required bool drivesEV}) {
    _drivesFuel = drivesFuel;
    _drivesEV = drivesEV;
    notifyListeners();
  }

  void reset() {
    _drivesFuel = true;
    _drivesEV = true;
    notifyListeners();
  }
}
