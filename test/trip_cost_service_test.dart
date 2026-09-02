import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/models/trip_models.dart';
import 'package:fuelgo_app/services/trip_cost_service.dart';

const fuelVehicle = SavedVehicle(
  id: 'fuel',
  year: 2020,
  make: 'Toyota',
  model: 'Camry',
  fuelType: 'Regular Gasoline',
  cityKmL: 12.3,
  highwayKmL: 17.4,
  combinedKmL: 14.5,
  combinedKwhPer100Km: null,
  isElectric: false,
  isFavourite: false,
);

const evVehicle = SavedVehicle(
  id: 'ev',
  year: 2024,
  make: 'BYD',
  model: 'Atto 3',
  fuelType: 'Electricity',
  cityKmL: 0,
  highwayKmL: 0,
  combinedKmL: 0,
  combinedKwhPer100Km: 15.5,
  isElectric: true,
  isFavourite: false,
);

const dieselVehicle = SavedVehicle(
  id: 'diesel',
  year: 2021,
  make: 'Isuzu',
  model: 'D-Max',
  fuelType: 'Diesel',
  cityKmL: 10,
  highwayKmL: 14,
  combinedKmL: 12,
  combinedKwhPer100Km: null,
  isElectric: false,
  isFavourite: false,
);

SavedVehicle vehicleWith({
  required String fuelType,
  double combinedKmL = 10,
  double? combinedKwhPer100Km,
  bool isElectric = false,
}) =>
    SavedVehicle(
      id: fuelType,
      year: 2024,
      make: 'Test',
      model: 'Vehicle',
      fuelType: fuelType,
      cityKmL: combinedKmL,
      highwayKmL: combinedKmL,
      combinedKmL: combinedKmL,
      combinedKwhPer100Km: combinedKwhPer100Km,
      isElectric: isElectric,
      isFavourite: false,
    );

void main() {
  test('fuel round-trip daily, weekly and monthly estimates', () {
    final result = TripCostService.calculate(
      const TripCalculationInput(
        mode: TripMode.daily,
        journeyType: JourneyType.roundTrip,
        oneWayDistanceKm: 18.4,
        vehicle: fuelVehicle,
        unitPrice: 2.05,
        travelDaysPerWeek: 5,
      ),
    );

    expect(result.totalDistanceKm, closeTo(36.8, .0001));
    expect(result.energyRequired, closeTo(36.8 / 14.5, .0001));
    expect(result.totalCost, closeTo((36.8 / 14.5) * 2.05, .0001));
    expect(result.weeklyCost, closeTo(result.totalCost * 5, .0001));
    expect(result.monthlyCost,
        closeTo(result.totalCost * 5 * TripCostService.weeksPerMonth, .0001));
  });

  test('EV long-distance estimate uses kWh per 100 km', () {
    final result = TripCostService.calculate(
      const TripCalculationInput(
        mode: TripMode.longDistance,
        journeyType: JourneyType.oneWay,
        oneWayDistanceKm: 300,
        vehicle: evVehicle,
        unitPrice: 1.2,
      ),
    );

    expect(result.energyRequired, closeTo(46.5, .0001));
    expect(result.totalCost, closeTo(55.8, .0001));
    expect(result.weeklyCost, isNull);
    expect(result.monthlyCost, isNull);
  });

  test('invalid days and zero prices are rejected', () {
    expect(
      () => TripCostService.calculate(
        const TripCalculationInput(
          mode: TripMode.daily,
          journeyType: JourneyType.oneWay,
          oneWayDistanceKm: 10,
          vehicle: fuelVehicle,
          unitPrice: 2,
          travelDaysPerWeek: 8,
        ),
      ),
      throwsA(isA<TripCalculationException>()),
    );
    expect(
      () => TripCostService.calculate(
        const TripCalculationInput(
          mode: TripMode.longDistance,
          journeyType: JourneyType.oneWay,
          oneWayDistanceKm: 10,
          vehicle: fuelVehicle,
          unitPrice: 0,
        ),
      ),
      throwsA(isA<TripCalculationException>()),
    );
  });

  test('one-way and round-trip distance math is deterministic', () {
    final oneWay = TripCostService.calculate(
      const TripCalculationInput(
        mode: TripMode.longDistance,
        journeyType: JourneyType.oneWay,
        oneWayDistanceKm: 120,
        vehicle: dieselVehicle,
        unitPrice: 3.15,
      ),
    );
    final roundTrip = TripCostService.calculate(
      const TripCalculationInput(
        mode: TripMode.longDistance,
        journeyType: JourneyType.roundTrip,
        oneWayDistanceKm: 120,
        vehicle: dieselVehicle,
        unitPrice: 3.15,
      ),
    );

    expect(oneWay.totalDistanceKm, 120);
    expect(roundTrip.totalDistanceKm, 240);
    expect(roundTrip.energyRequired, closeTo(oneWay.energyRequired * 2, .0001));
    expect(roundTrip.totalCost, closeTo(oneWay.totalCost * 2, .0001));
  });

  test('all valid travel day values use the 4.33 monthly multiplier', () {
    for (var days = 1; days <= 7; days++) {
      final result = TripCostService.calculate(
        TripCalculationInput(
          mode: TripMode.daily,
          journeyType: JourneyType.oneWay,
          oneWayDistanceKm: 10,
          vehicle: fuelVehicle,
          unitPrice: 2,
          travelDaysPerWeek: days,
        ),
      );
      expect(result.weeklyCost, closeTo(result.totalCost * days, .0001));
      expect(
        result.monthlyCost,
        closeTo(result.weeklyCost! * 4.33, .0001),
      );
    }
  });

  test('missing efficiencies are rejected for fuel and EV vehicles', () {
    final noFuelEfficiency = vehicleWith(
      fuelType: 'Regular Gasoline',
      combinedKmL: 0,
    );
    final noEvEfficiency = vehicleWith(
      fuelType: 'Electricity',
      combinedKmL: 0,
      isElectric: true,
    );

    for (final vehicle in [noFuelEfficiency, noEvEfficiency]) {
      expect(
        () => TripCostService.calculate(
          TripCalculationInput(
            mode: TripMode.longDistance,
            journeyType: JourneyType.oneWay,
            oneWayDistanceKm: 10,
            vehicle: vehicle,
            unitPrice: 2,
          ),
        ),
        throwsA(isA<TripCalculationException>()),
      );
    }
  });

  test('PHEV and unsupported powertrains are rejected', () {
    final vehicles = [
      vehicleWith(
        fuelType: 'Premium Gasoline or Electricity',
        isElectric: true,
      ),
      vehicleWith(fuelType: 'CNG'),
    ];

    for (final vehicle in vehicles) {
      expect(
        () => TripCostService.calculate(
          TripCalculationInput(
            mode: TripMode.longDistance,
            journeyType: JourneyType.oneWay,
            oneWayDistanceKm: 10,
            vehicle: vehicle,
            unitPrice: 2,
          ),
        ),
        throwsA(isA<TripCalculationException>()),
      );
    }
  });

  test('invalid distance and non-finite inputs are rejected', () {
    for (final distance in [0.0, -1.0, double.infinity]) {
      expect(
        () => TripCostService.calculate(
          TripCalculationInput(
            mode: TripMode.longDistance,
            journeyType: JourneyType.oneWay,
            oneWayDistanceKm: distance,
            vehicle: fuelVehicle,
            unitPrice: 2,
          ),
        ),
        throwsA(isA<TripCalculationException>()),
      );
    }
  });
}
