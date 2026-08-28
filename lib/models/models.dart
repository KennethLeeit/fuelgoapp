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
  final String? imageUrl;
  final String? website;

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
    this.imageUrl,
    this.website,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'distanceKm': distanceKm,
        'open24Hours': open24Hours,
        'openingHoursRaw': openingHoursRaw,
        'fuelTypes': fuelTypes,
        'services': services,
        'brandColor': brandColor.toARGB32(),
        'imageUrl': imageUrl,
        'website': website,
      };

  factory FuelStation.fromJson(Map<String, dynamic> json) => FuelStation(
        id: json['id'] as String,
        name: json['name'] as String,
        brand: json['brand'] as String?,
        address: json['address'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        open24Hours: json['open24Hours'] as bool?,
        openingHoursRaw: json['openingHoursRaw'] as String?,
        fuelTypes: List<String>.from(json['fuelTypes'] as List? ?? const []),
        services: List<String>.from(json['services'] as List? ?? const []),
        brandColor: Color((json['brandColor'] as num).toInt()),
        imageUrl: json['imageUrl'] as String?,
        website: json['website'] as String?,
      );

  bool get hasReadableAddress {
    final value = address.trim();
    if (value.isEmpty || value == 'Address not provided') return false;
    return !RegExp(r'^-?\d{1,3}(?:\.\d+)?,\s*-?\d{1,3}(?:\.\d+)?$')
        .hasMatch(value);
  }

  String get displayAddress =>
      hasReadableAddress ? address : 'Exact location available in map';

  Color get displayBrandColor => colorForName(
        brand?.trim().isNotEmpty == true ? brand : name,
      );
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
  final value = name?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ?? '';
  if (value.contains('petronas')) return const Color(0xFF00A19B);
  if (value.contains('shell')) return const Color(0xFFFFD500);
  if (value.contains('bhpetrol') || value == 'bhp') {
    return const Color(0xFFF37021);
  }
  if (value.contains('petron')) return const Color(0xFF003B7A);
  if (value.contains('caltex') || value.contains('chevron')) {
    return const Color(0xFFD71920);
  }
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
