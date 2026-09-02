import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/models/trip_models.dart';

void main() {
  test('legacy EV consumption converts from 100 miles to 100 km', () {
    final vehicle = SavedVehicle.fromMap('ev', {
      'make': 'Test',
      'model': 'EV',
      'fuelType': 'Electricity',
      'isElectric': true,
      'combinedKwhPer100Miles': 24.14016,
    });

    expect(vehicle.powertrain, VehiclePowertrain.electric);
    expect(vehicle.combinedKwhPer100Km, closeTo(15, .0001));
  });

  test('PHEV is distinguished from pure EV and HEV petrol flow', () {
    final phev = SavedVehicle.fromMap('phev', {
      'fuelType': 'Premium Gasoline or Electricity',
      'isElectric': true,
    });
    final hev = SavedVehicle.fromMap('hev', {
      'fuelType': 'Regular Gasoline',
      'isElectric': false,
      'combinedKmL': 20,
    });

    expect(phev.powertrain, VehiclePowertrain.plugInHybrid);
    expect(hev.powertrain, VehiclePowertrain.petrol);
  });

  test('metric EV efficiency takes precedence over the legacy value', () {
    final vehicle = SavedVehicle.fromMap('ev', {
      'fuelType': 'Electricity',
      'isElectric': true,
      'combinedKwhPer100Km': 16.2,
      'combinedKwhPer100Miles': 99,
    });

    expect(vehicle.combinedKwhPer100Km, 16.2);
  });

  test('diesel, petrol and unsupported fuels classify deterministically', () {
    expect(
      SavedVehicle.fromMap('diesel', {'fuelType': 'Diesel'}).powertrain,
      VehiclePowertrain.diesel,
    );
    expect(
      SavedVehicle.fromMap('petrol', {'fuelType': 'RON95'}).powertrain,
      VehiclePowertrain.petrol,
    );
    expect(
      SavedVehicle.fromMap('ethanol', {'fuelType': 'E85'}).powertrain,
      VehiclePowertrain.unsupported,
    );
  });

  test('trip place map conversion preserves coordinates and labels', () {
    const place = TripPlace(
      name: 'KLCC',
      address: 'Kuala Lumpur, Malaysia',
      latitude: 3.1579,
      longitude: 101.7123,
    );

    final restored = TripPlace.fromMap(place.toMap());
    expect(restored.name, place.name);
    expect(restored.address, place.address);
    expect(restored.latitude, place.latitude);
    expect(restored.longitude, place.longitude);
  });
}
