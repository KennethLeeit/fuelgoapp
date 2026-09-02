import 'package:cloud_firestore/cloud_firestore.dart';

enum TripMode { daily, longDistance }

enum JourneyType { oneWay, roundTrip }

enum VehiclePowertrain { petrol, diesel, electric, plugInHybrid, unsupported }

extension TripModeValue on TripMode {
  String get key => this == TripMode.daily ? 'daily' : 'longDistance';
  String get label =>
      this == TripMode.daily ? 'Daily / Regular Route' : 'Long Distance Trip';

  static TripMode fromKey(String? value) =>
      value == 'longDistance' ? TripMode.longDistance : TripMode.daily;
}

extension JourneyTypeValue on JourneyType {
  String get key => this == JourneyType.roundTrip ? 'roundTrip' : 'oneWay';
  String get label => this == JourneyType.roundTrip ? 'Round Trip' : 'One Way';
  int get distanceMultiplier => this == JourneyType.roundTrip ? 2 : 1;

  static JourneyType fromKey(String? value) =>
      value == 'roundTrip' ? JourneyType.roundTrip : JourneyType.oneWay;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

class TripPlace {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const TripPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  factory TripPlace.fromMap(Map<String, dynamic> data) => TripPlace(
        name: (data['name'] ?? data['label'] ?? '').toString(),
        address: (data['address'] ?? data['label'] ?? '').toString(),
        latitude: _asDouble(data['latitude']),
        longitude: _asDouble(data['longitude']),
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
      };
}

class SavedVehicle {
  static const double milesPerKilometre = 1.609344;

  final String id;
  final int year;
  final String make;
  final String model;
  final String fuelType;
  final double cityKmL;
  final double highwayKmL;
  final double combinedKmL;
  final double? combinedKwhPer100Km;
  final bool isElectric;
  final bool isFavourite;

  const SavedVehicle({
    required this.id,
    required this.year,
    required this.make,
    required this.model,
    required this.fuelType,
    required this.cityKmL,
    required this.highwayKmL,
    required this.combinedKmL,
    required this.combinedKwhPer100Km,
    required this.isElectric,
    required this.isFavourite,
  });

  factory SavedVehicle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      SavedVehicle.fromMap(doc.id, doc.data() ?? const {});

  factory SavedVehicle.fromMap(String id, Map<String, dynamic> data) {
    final metricElectricity = _asDouble(data['combinedKwhPer100Km']);
    final imperialElectricity = _asDouble(data['combinedKwhPer100Miles']);
    return SavedVehicle(
      id: id,
      year: _asInt(data['year']),
      make: (data['make'] ?? '').toString(),
      model: (data['model'] ?? '').toString(),
      fuelType: (data['fuelType'] ?? '').toString(),
      cityKmL: _asDouble(data['cityKmL']),
      highwayKmL: _asDouble(data['highwayKmL']),
      combinedKmL: _asDouble(data['combinedKmL']),
      combinedKwhPer100Km: metricElectricity > 0
          ? metricElectricity
          : imperialElectricity > 0
              ? imperialElectricity / milesPerKilometre
              : null,
      isElectric: data['isElectric'] as bool? ?? false,
      isFavourite: data['isFavourite'] as bool? ?? false,
    );
  }

  String get label {
    final vehicle =
        [make, model].where((part) => part.trim().isNotEmpty).join(' ');
    return year > 0 ? '$year $vehicle' : vehicle;
  }

  VehiclePowertrain get powertrain {
    final value = fuelType.toLowerCase();
    final hasElectricity = isElectric || value.contains('electric');
    final hasCombustion = value.contains('gas') ||
        value.contains('petrol') ||
        value.contains('diesel');
    if (hasElectricity && hasCombustion) return VehiclePowertrain.plugInHybrid;
    if (hasElectricity) return VehiclePowertrain.electric;
    if (value.contains('diesel')) return VehiclePowertrain.diesel;
    if (value.contains('gasoline') ||
        value.contains('petrol') ||
        value.contains('ron95') ||
        value.contains('ron97') ||
        value.contains('premium') ||
        value.contains('regular')) {
      return VehiclePowertrain.petrol;
    }
    return VehiclePowertrain.unsupported;
  }

  bool get requiresPremiumFuel =>
      fuelType.toLowerCase().contains('premium') ||
      fuelType.toLowerCase().contains('ron97');
}

class TripCalculationInput {
  final TripMode mode;
  final JourneyType journeyType;
  final double oneWayDistanceKm;
  final SavedVehicle vehicle;
  final double unitPrice;
  final int? travelDaysPerWeek;

  const TripCalculationInput({
    required this.mode,
    required this.journeyType,
    required this.oneWayDistanceKm,
    required this.vehicle,
    required this.unitPrice,
    this.travelDaysPerWeek,
  });
}

class TripCalculationResult {
  final double oneWayDistanceKm;
  final double totalDistanceKm;
  final double energyRequired;
  final double totalCost;
  final double? weeklyCost;
  final double? monthlyCost;
  final bool isElectric;

  const TripCalculationResult({
    required this.oneWayDistanceKm,
    required this.totalDistanceKm,
    required this.energyRequired,
    required this.totalCost,
    required this.weeklyCost,
    required this.monthlyCost,
    required this.isElectric,
  });
}

class SavedRoute {
  final String id;
  final String userId;
  final String name;
  final TripPlace origin;
  final TripPlace destination;
  final double oneWayDistanceKm;
  final String vehicleId;
  final String vehicleLabelSnapshot;
  final TripMode mode;
  final JourneyType journeyType;
  final int? travelDaysPerWeek;
  final String? fuelType;
  final String? chargingProvider;

  const SavedRoute({
    required this.id,
    required this.userId,
    required this.name,
    required this.origin,
    required this.destination,
    required this.oneWayDistanceKm,
    required this.vehicleId,
    required this.vehicleLabelSnapshot,
    required this.mode,
    required this.journeyType,
    required this.travelDaysPerWeek,
    required this.fuelType,
    required this.chargingProvider,
  });

  factory SavedRoute.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SavedRoute(
      id: doc.id,
      userId: (data['userId'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      origin: TripPlace.fromMap(
          Map<String, dynamic>.from(data['origin'] ?? const {})),
      destination: TripPlace.fromMap(
          Map<String, dynamic>.from(data['destination'] ?? const {})),
      oneWayDistanceKm: _asDouble(data['oneWayDistanceKm']),
      vehicleId: (data['vehicleId'] ?? '').toString(),
      vehicleLabelSnapshot: (data['vehicleLabelSnapshot'] ?? '').toString(),
      mode: TripModeValue.fromKey(data['mode'] as String?),
      journeyType: JourneyTypeValue.fromKey(data['journeyType'] as String?),
      travelDaysPerWeek: data['travelDaysPerWeek'] == null
          ? null
          : _asInt(data['travelDaysPerWeek']),
      fuelType: data['fuelType'] as String?,
      chargingProvider: data['chargingProvider'] as String?,
    );
  }

  Map<String, dynamic> toFirestore({required bool create}) => {
        'userId': userId,
        'name': name.trim(),
        'origin': origin.toMap(),
        'destination': destination.toMap(),
        'oneWayDistanceKm': oneWayDistanceKm,
        'vehicleId': vehicleId,
        'vehicleLabelSnapshot': vehicleLabelSnapshot,
        'mode': mode.key,
        'journeyType': journeyType.key,
        'travelDaysPerWeek': mode == TripMode.daily ? travelDaysPerWeek : null,
        'fuelType': fuelType,
        'chargingProvider': chargingProvider,
        if (create) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  SavedRoute copyWith({String? id, String? name}) => SavedRoute(
        id: id ?? this.id,
        userId: userId,
        name: name ?? this.name,
        origin: origin,
        destination: destination,
        oneWayDistanceKm: oneWayDistanceKm,
        vehicleId: vehicleId,
        vehicleLabelSnapshot: vehicleLabelSnapshot,
        mode: mode,
        journeyType: journeyType,
        travelDaysPerWeek: travelDaysPerWeek,
        fuelType: fuelType,
        chargingProvider: chargingProvider,
      );
}
