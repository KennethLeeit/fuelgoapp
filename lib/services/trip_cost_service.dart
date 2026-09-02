import '../models/trip_models.dart';

class TripCalculationException implements Exception {
  final String message;
  const TripCalculationException(this.message);
  @override
  String toString() => message;
}

class TripCostService {
  static const double weeksPerMonth = 4.33;

  static TripCalculationResult calculate(TripCalculationInput input) {
    if (!input.oneWayDistanceKm.isFinite || input.oneWayDistanceKm <= 0) {
      throw const TripCalculationException(
          'A valid driving distance is required.');
    }
    if (!input.unitPrice.isFinite || input.unitPrice <= 0) {
      throw const TripCalculationException(
          'A valid fuel or charging price is unavailable.');
    }
    if (input.mode == TripMode.daily &&
        (input.travelDaysPerWeek == null ||
            input.travelDaysPerWeek! < 1 ||
            input.travelDaysPerWeek! > 7)) {
      throw const TripCalculationException(
          'Travel days must be between 1 and 7.');
    }

    final powertrain = input.vehicle.powertrain;
    if (powertrain == VehiclePowertrain.plugInHybrid) {
      throw const TripCalculationException(
          'Plug-in hybrid vehicles are not supported in this version.');
    }
    if (powertrain == VehiclePowertrain.unsupported) {
      throw const TripCalculationException(
          'This vehicle fuel type is not supported.');
    }

    final totalDistance =
        input.oneWayDistanceKm * input.journeyType.distanceMultiplier;
    final isElectric = powertrain == VehiclePowertrain.electric;
    late final double energy;
    if (isElectric) {
      final efficiency = input.vehicle.combinedKwhPer100Km;
      if (efficiency == null || !efficiency.isFinite || efficiency <= 0) {
        throw const TripCalculationException(
            'This EV has no usable energy-efficiency information.');
      }
      energy = totalDistance * efficiency / 100;
    } else {
      final efficiency = input.vehicle.combinedKmL;
      if (!efficiency.isFinite || efficiency <= 0) {
        throw const TripCalculationException(
            'This vehicle has no usable combined fuel efficiency.');
      }
      energy = totalDistance / efficiency;
    }

    final cost = energy * input.unitPrice;
    final weekly =
        input.mode == TripMode.daily ? cost * input.travelDaysPerWeek! : null;
    return TripCalculationResult(
      oneWayDistanceKm: input.oneWayDistanceKm,
      totalDistanceKm: totalDistance,
      energyRequired: energy,
      totalCost: cost,
      weeklyCost: weekly,
      monthlyCost: weekly == null ? null : weekly * weeksPerMonth,
      isElectric: isElectric,
    );
  }
}
