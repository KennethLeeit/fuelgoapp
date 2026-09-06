import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FuelStation {
  final String id;
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

  static const List<String> _commonDefaultServices = ['Toilet', 'Shop', 'ATM'];

  List<String> get displayServices =>
      services.isNotEmpty ? services : _commonDefaultServices;
}

class EVCharger {
  final String id;
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

  bool get hasReadableAddress {
    final value = address.trim();
    if (value.isEmpty || value == 'Address not available') return false;
    return !RegExp(r'^-?\d{1,3}(?:\.\d+)?,\s*-?\d{1,3}(?:\.\d+)?$')
        .hasMatch(value);
  }
}

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

class ReviewerLevel {
  final int tier;
  final String name;
  final IconData icon;
  final Color color;
  final int minReviews;
  final int? nextTierAt;

  const ReviewerLevel({
    required this.tier,
    required this.name,
    required this.icon,
    required this.color,
    required this.minReviews,
    required this.nextTierAt,
  });

  static const List<ReviewerLevel> _tiers = [
    ReviewerLevel(
      tier: 1,
      name: 'New Reviewer',
      icon: Icons.eco_outlined,
      color: Color(0xFF78909C),
      minReviews: 0,
      nextTierAt: 3,
    ),
    ReviewerLevel(
      tier: 2,
      name: 'Contributor',
      icon: Icons.rate_review_outlined,
      color: Color(0xFF42A5F5),
      minReviews: 3,
      nextTierAt: 8,
    ),
    ReviewerLevel(
      tier: 3,
      name: 'Trusted Reviewer',
      icon: Icons.verified_outlined,
      color: Color(0xFF26A69A),
      minReviews: 8,
      nextTierAt: 16,
    ),
    ReviewerLevel(
      tier: 4,
      name: 'Local Guide',
      icon: Icons.explore_outlined,
      color: Color(0xFF7E57C2),
      minReviews: 16,
      nextTierAt: 31,
    ),
    ReviewerLevel(
      tier: 5,
      name: 'Elite Local Guide',
      icon: Icons.workspace_premium_outlined,
      color: Color(0xFFFFB300),
      minReviews: 31,
      nextTierAt: null,
    ),
  ];

  static ReviewerLevel forCount(int count) {
    ReviewerLevel current = _tiers.first;
    for (final t in _tiers) {
      if (count >= t.minReviews) current = t;
    }
    return current;
  }

  static List<ReviewerLevel> get allTiers => List.unmodifiable(_tiers);

  int? reviewsToNextTier(int count) =>
      nextTierAt == null ? null : nextTierAt! - count;
}

enum ReviewStationType { fuel, ev }

extension ReviewStationTypeX on ReviewStationType {
  String get key => this == ReviewStationType.fuel ? 'fuel' : 'ev';

  static ReviewStationType fromKey(String key) =>
      key == 'ev' ? ReviewStationType.ev : ReviewStationType.fuel;
}

class Review {
  final String id;
  final String stationId;
  final ReviewStationType stationType;

  final String stationName;
  final String userId;
  final String userName;
  final int rating;
  final String comment;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Review({
    required this.id,
    required this.stationId,
    required this.stationType,
    required this.stationName,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    this.createdAt,
    this.updatedAt,
  });

  factory Review.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? asDate(dynamic value) =>
        value is Timestamp ? value.toDate() : null;
    return Review(
      id: id,
      stationId: data['stationId'] as String? ?? '',
      stationType:
          ReviewStationTypeX.fromKey(data['stationType'] as String? ?? 'fuel'),
      stationName: (data['stationName'] as String?)?.trim().isNotEmpty == true
          ? data['stationName'] as String
          : 'Unknown location',
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
