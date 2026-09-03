import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/models/trip_models.dart';
import 'package:fuelgo_app/services/fuel_price_impact_service.dart';
import 'package:fuelgo_app/services/fuel_price_service.dart';

void main() {
  const vehicle = SavedVehicle(
    id: 'v1',
    year: 2020,
    make: 'Test',
    model: 'Car',
    fuelType: 'Gasoline',
    cityKmL: 10,
    highwayKmL: 10,
    combinedKmL: 10,
    combinedKwhPer100Km: null,
    isElectric: false,
    isFavourite: false,
  );
  const place =
      TripPlace(name: 'Place', address: 'Place', latitude: 3, longitude: 101);
  const route = SavedRoute(
    id: 'r1',
    userId: 'u1',
    name: 'Work',
    origin: place,
    destination: TripPlace(
        name: 'Work', address: 'Work', latitude: 3.1, longitude: 101.1),
    oneWayDistanceKm: 10,
    vehicleId: 'v1',
    vehicleLabelSnapshot: 'Test Car',
    mode: TripMode.daily,
    journeyType: JourneyType.roundTrip,
    travelDaysPerWeek: 5,
    fuelType: 'RON97',
    chargingProvider: null,
  );

  test('parses latest and immediately previous official level rows', () {
    final snapshot = FuelPriceService.parseRows([
      {
        'date': '2026-08-20',
        'series_type': 'level',
        'ron95': 2.0,
        'ron97': 3.1,
        'diesel': 2.9,
        'diesel_eastmsia': 2.2,
      },
      {
        'date': '2026-08-27',
        'series_type': 'level',
        'ron95': 2.05,
        'ron97': 3.2,
        'diesel': 3.0,
        'diesel_eastmsia': 2.25,
      },
      {
        'date': '2026-08-27',
        'series_type': 'change_weekly',
        'ron95': .05,
        'ron97': .1,
        'diesel': .1,
      },
    ]);

    expect(snapshot.ron97, 3.2);
    expect(snapshot.previousRon97, 3.1);
    expect(snapshot.previousDate, DateTime(2026, 8, 20));
    expect(snapshot.dieselEastMalaysia, 2.25);
  });

  test('calculates weekly and monthly route impact through trip cost logic',
      () {
    final prices = FuelPriceSnapshot(
      date: DateTime(2026, 8, 27),
      previousDate: DateTime(2026, 8, 20),
      ron95: 2.05,
      ron97: 3.2,
      diesel: 3,
      previousRon95: 2,
      previousRon97: 3.1,
      previousDiesel: 2.9,
      ron95Change: .05,
      ron97Change: .1,
      dieselChange: .1,
    );
    final impact = FuelPriceImpactService.calculate(route, vehicle, prices)!;

    expect(impact.previousCost.weeklyCost, closeTo(31, .001));
    expect(impact.currentCost.weeklyCost, closeTo(32, .001));
    expect(impact.weeklyDifference, closeTo(1, .001));
    expect(impact.monthlyDifference, closeTo(4.33, .001));
  });

  test('does not claim impact for configured subsidised rate', () {
    final prices = FuelPriceSnapshot(
      date: DateTime(2026),
      ron95: 2,
      ron97: 3,
      diesel: 3,
      previousRon95: 1.9,
      previousRon97: 2.9,
      previousDiesel: 2.9,
      ron95Change: 0,
      ron97Change: 0,
      dieselChange: 0,
    );
    final subsidised = route.copyWith(name: 'Subsidised');
    final replacement = SavedRoute(
      id: subsidised.id,
      userId: subsidised.userId,
      name: subsidised.name,
      origin: subsidised.origin,
      destination: subsidised.destination,
      oneWayDistanceKm: subsidised.oneWayDistanceKm,
      vehicleId: subsidised.vehicleId,
      vehicleLabelSnapshot: subsidised.vehicleLabelSnapshot,
      mode: subsidised.mode,
      journeyType: subsidised.journeyType,
      travelDaysPerWeek: subsidised.travelDaysPerWeek,
      fuelType: 'RON95 (Subsidised)',
      chargingProvider: null,
    );
    expect(
        FuelPriceImpactService.calculate(replacement, vehicle, prices), isNull);
  });

  test('unsubsidised RON95 is included in fuel price impact', () {
    final prices = FuelPriceSnapshot(
      date: DateTime(2026, 8, 27),
      ron95: 2.1,
      ron97: 3,
      diesel: 3,
      previousRon95: 2,
      previousRon97: 3,
      previousDiesel: 3,
      ron95Change: .1,
      ron97Change: 0,
      dieselChange: 0,
    );
    final unsubsidisedRoute = SavedRoute(
      id: route.id,
      userId: route.userId,
      name: route.name,
      origin: route.origin,
      destination: route.destination,
      oneWayDistanceKm: route.oneWayDistanceKm,
      vehicleId: route.vehicleId,
      vehicleLabelSnapshot: route.vehicleLabelSnapshot,
      mode: route.mode,
      journeyType: route.journeyType,
      travelDaysPerWeek: route.travelDaysPerWeek,
      fuelType: 'RON95 (Unsubsidised)',
      chargingProvider: null,
    );

    final impact = FuelPriceImpactService.calculate(
      unsubsidisedRoute,
      vehicle,
      prices,
    );
    expect(impact, isNotNull);
    expect(impact!.weeklyDifference, closeTo(1, .001));
  });

  test('identifies only official fuels used by saved routes', () {
    expect(
      FuelPriceImpactService.officialFuelKey('RON95 (Unsubsidised)'),
      'ron95',
    );
    expect(FuelPriceImpactService.officialFuelKey('RON97'), 'ron97');
    expect(FuelPriceImpactService.officialFuelKey('Diesel'), 'diesel');
    expect(
      FuelPriceImpactService.officialFuelKey('RON95 (Subsidised)'),
      isNull,
    );
    expect(FuelPriceImpactService.officialFuelKey(null), isNull);
  });
}
