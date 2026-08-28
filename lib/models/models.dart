import 'package:flutter/material.dart';

/// A fuel station, populated from live OpenStreetMap (Overpass API) data.
/// Note: OSM has no star-rating data, so [rating]/[reviewCount] are always
/// null — the UI hides that row when null rather than showing a fake value.
class FuelStation {
  final String id; // stable OSM id, e.g. "node/12345"
  final String name;
  final String? brand;
  final String address;
  final double latitude;
  final double longitude;
  double distanceKm;
  final bool? open24Hours;
  final String? openingHoursRaw;
  final List<String> fuelTypes;
  final List<String> services;
  final Color brandColor;

  FuelStation({
    required this.id,
    required this.name,
    this.brand,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.distanceKm = 0,
    this.open24Hours,
    this.openingHoursRaw,
    this.fuelTypes = const [],
    this.services = const [],
    required this.brandColor,
  });
}

/// An EV charger, populated from live Open Charge Map data.
/// Note: OCM has no star-rating data, so [rating]/[reviewCount] are always
/// null. Pricing (if present at all) comes through as free-text
/// [usageCostRaw] since operators don't publish a clean per-kWh number.
class EVCharger {
  final String id; // stable OCM POI id
  final String name;
  final String? operatorName;
  final String address;
  final double latitude;
  final double longitude;
  double distanceKm;
  final List<String> connectors;
  final int? maxPowerKw;
  final String? usageCostRaw;
  final bool? operational;

  EVCharger({
    required this.id,
    required this.name,
    this.operatorName,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.distanceKm = 0,
    this.connectors = const [],
    this.maxPowerKw,
    this.usageCostRaw,
    this.operational,
  });
}

/// Deterministic color per brand/operator name, so real-world brands still
/// get a stable, distinct color without needing a hand-curated lookup table.
Color colorForName(String? name) {
  const palette = [
    Color(0xFF00A99D),
    Color(0xFFED1C24),
    Color(0xFF1B3F94),
    Color(0xFFEE7623),
    Color(0xFFE0102A),
    Color(0xFF27AE60),
    Color(0xFF00AEEF),
    Color(0xFF2ECC71),
    Color(0xFF8E44AD),
    Color(0xFF2F6FED),
  ];
  if (name == null || name.isEmpty) return palette[0];
  final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
  return palette[hash % palette.length];
}
