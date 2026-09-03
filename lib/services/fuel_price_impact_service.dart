import '../models/trip_models.dart';
import 'fuel_price_service.dart';
import 'trip_cost_service.dart';

class FuelRouteImpact {
  final SavedRoute route;
  final SavedVehicle vehicle;
  final double previousUnitPrice;
  final double currentUnitPrice;
  final TripCalculationResult previousCost;
  final TripCalculationResult currentCost;

  const FuelRouteImpact({
    required this.route,
    required this.vehicle,
    required this.previousUnitPrice,
    required this.currentUnitPrice,
    required this.previousCost,
    required this.currentCost,
  });

  double get weeklyDifference =>
      currentCost.weeklyCost! - previousCost.weeklyCost!;
  double get monthlyDifference =>
      currentCost.monthlyCost! - previousCost.monthlyCost!;
}

class FuelPriceImpactService {
  /// Returns the official pump-price series used by a saved route.
  ///
  /// Subsidised RON95 is intentionally excluded because Fuel Go uses a
  /// configured reference rate for it, not the official weekly series.
  static String? officialFuelKey(String? fuelType) {
    final value = (fuelType ?? '').toLowerCase().replaceAll('z', 's');
    if (value.contains('unsubsidised') && value.contains('95')) {
      return 'ron95';
    }
    if (value.contains('subsidised')) return null;
    if (value.contains('97')) return 'ron97';
    if (value.contains('95')) return 'ron95';
    if (value.contains('diesel')) return 'diesel';
    return null;
  }

  static FuelRouteImpact? calculate(
    SavedRoute route,
    SavedVehicle vehicle,
    FuelPriceSnapshot prices,
  ) {
    if (route.mode != TripMode.daily ||
        route.travelDaysPerWeek == null ||
        route.chargingProvider != null ||
        vehicle.powertrain == VehiclePowertrain.electric ||
        route.oneWayDistanceKm <= 0) {
      return null;
    }
    final pair = _pricePair(route, prices);
    if (pair == null || pair.$1 <= 0 || pair.$2 <= 0) return null;
    final base = TripCalculationInput(
      mode: TripMode.daily,
      journeyType: route.journeyType,
      oneWayDistanceKm: route.oneWayDistanceKm,
      vehicle: vehicle,
      unitPrice: pair.$1,
      travelDaysPerWeek: route.travelDaysPerWeek,
    );
    final previous = TripCostService.calculate(base);
    final current = TripCostService.calculate(TripCalculationInput(
      mode: base.mode,
      journeyType: base.journeyType,
      oneWayDistanceKm: base.oneWayDistanceKm,
      vehicle: base.vehicle,
      unitPrice: pair.$2,
      travelDaysPerWeek: base.travelDaysPerWeek,
    ));
    return FuelRouteImpact(
      route: route,
      vehicle: vehicle,
      previousUnitPrice: pair.$1,
      currentUnitPrice: pair.$2,
      previousCost: previous,
      currentCost: current,
    );
  }

  static (double, double)? _pricePair(
      SavedRoute route, FuelPriceSnapshot prices) {
    switch (officialFuelKey(route.fuelType)) {
      case 'ron95':
        return (prices.previousRon95 ?? 0, prices.ron95);
      case 'ron97':
        return (prices.previousRon97 ?? 0, prices.ron97);
      case 'diesel':
        final inEastMalaysia =
            route.origin.longitude > 109 || route.destination.longitude > 109;
        if (inEastMalaysia && prices.dieselEastMalaysia > 0) {
          return (
            prices.previousDieselEastMalaysia ?? 0,
            prices.dieselEastMalaysia,
          );
        }
        return (prices.previousDiesel ?? 0, prices.diesel);
      default:
        return null;
    }
  }
}
