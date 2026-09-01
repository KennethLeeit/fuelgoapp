import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'operatorName': operatorName,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'distanceKm': distanceKm,
        'connectors': connectors,
        'maxPowerKw': maxPowerKw,
        'usageCostRaw': usageCostRaw,
        'operational': operational,
      };

  factory EVCharger.fromJson(Map<String, dynamic> json) => EVCharger(
        id: json['id'] as String,
        name: json['name'] as String,
        operatorName: json['operatorName'] as String?,
        address: json['address'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
        connectors: List<String>.from(json['connectors'] as List? ?? const []),
        maxPowerKw: (json['maxPowerKw'] as num?)?.toInt(),
        usageCostRaw: json['usageCostRaw'] as String?,
        operational: json['operational'] as bool?,
      );
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

/// Which kind of place a [Review] belongs to. Kept as its own type (rather
/// than a raw string) so a typo like "Fuel" vs "fuel" can't silently split
/// a station's reviews into two groups.
enum ReviewStationType { fuel, ev }

extension ReviewStationTypeX on ReviewStationType {
  String get key => this == ReviewStationType.fuel ? 'fuel' : 'ev';

  static ReviewStationType fromKey(String key) =>
      key == 'ev' ? ReviewStationType.ev : ReviewStationType.fuel;
}

/// A single user's star rating + written review for one fuel station or
/// EV charger — the Google-Maps-style review feature. Backed by Firestore
/// (see ReviewService) so reviews are shared across everyone using the
/// app, not just stored locally like favourites.
class Review {
  final String id; // Firestore document id
  final String stationId;
  final ReviewStationType stationType;
  final String userId;
  final String userName;
  final int rating; // 1–5
  final String comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Review({
    required this.id,
    required this.stationId,
    required this.stationType,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    this.createdAt,
    this.updatedAt,
  });

  factory Review.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? asDate(dynamic value) => value is Timestamp ? value.toDate() : null;
    return Review(
      id: id,
      stationId: data['stationId'] as String? ?? '',
      stationType: ReviewStationTypeX.fromKey(data['stationType'] as String? ?? 'fuel'),
      userId: data['userId'] as String? ?? '',
      userName: (data['userName'] as String?)?.trim().isNotEmpty == true
          ? data['userName'] as String
          : 'FuelGo user',
      rating: ((data['rating'] as num?) ?? 5).toInt().clamp(1, 5),
      comment: data['comment'] as String? ?? '',
      createdAt: asDate(data['createdAt']),
      updatedAt: asDate(data['updatedAt']),
    );
  }
}
