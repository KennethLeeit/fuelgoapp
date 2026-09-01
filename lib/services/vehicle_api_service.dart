import 'dart:convert';
import 'package:http/http.dart' as http;

/// A single entry from one of the fueleconomy.gov cascading selection
/// menus (year / make / model / trim options).
///
/// See https://www.fueleconomy.gov/feg/ws/index.shtml
class VehicleMenuItem {
  final String text;
  final String value;

  const VehicleMenuItem({required this.text, required this.value});

  factory VehicleMenuItem.fromJson(Map<String, dynamic> json) {
    return VehicleMenuItem(
      text: (json['text'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
    );
  }

  @override
  String toString() => text;
}

/// Fuel-economy details for one specific vehicle configuration, as
/// returned by GET /ws/rest/vehicle/{id}.
class VehicleFuelEconomy {
  final int id;
  final String year;
  final String make;
  final String model;
  final String trans;
  final String drive;
  final String fuelType;
  final int cityMpg;
  final int highwayMpg;
  final int combinedMpg;
  final bool isElectric;

  /// Combined electricity consumption in kWh per 100 miles.
  /// Only present for EVs / plug-in hybrids.
  final double? combinedKwhPer100Miles;

  const VehicleFuelEconomy({
    required this.id,
    required this.year,
    required this.make,
    required this.model,
    required this.trans,
    required this.drive,
    required this.fuelType,
    required this.cityMpg,
    required this.highwayMpg,
    required this.combinedMpg,
    required this.isElectric,
    this.combinedKwhPer100Miles,
  });

  factory VehicleFuelEconomy.fromJson(Map<String, dynamic> json) {
    final fuelType1 = (json['fuelType1'] ?? json['fuelType'] ?? '').toString();
    final isElectric = fuelType1.toLowerCase().contains('electricity');
    return VehicleFuelEconomy(
      id: _asInt(json['id']),
      year: (json['year'] ?? '').toString(),
      make: (json['make'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      trans: (json['trany'] ?? '').toString(),
      drive: (json['drive'] ?? '').toString(),
      fuelType: fuelType1,
      // Per fueleconomy.gov docs, city08/highway08/comb08 are already
      // expressed as MPGe for electric and CNG vehicles.
      cityMpg: _asInt(json['city08']),
      highwayMpg: _asInt(json['highway08']),
      combinedMpg: _asInt(json['comb08']),
      isElectric: isElectric,
      combinedKwhPer100Miles: _asDouble(json['combE']),
    );
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    final parsed = double.tryParse(v.toString());
    // The API returns 0 for "not applicable" on non-EVs; treat that as null.
    return (parsed == null || parsed == 0) ? null : parsed;
  }
}

/// Thrown when a fueleconomy.gov request fails or returns something we
/// can't parse.
class VehicleApiException implements Exception {
  final String message;
  VehicleApiException(this.message);
  @override
  String toString() => message;
}

/// Thin client for the public fueleconomy.gov "Find a Car" web service.
///
/// Docs: https://www.fueleconomy.gov/feg/ws/index.shtml
class VehicleApiService {
  static const _baseUrl = 'https://www.fueleconomy.gov/ws/rest/vehicle';

  // fueleconomy.gov returns XML by default; asking for JSON explicitly
  // is what unlocks jsonDecode()-friendly responses below.
  static const _jsonHeaders = {'Accept': 'application/json'};

  /// All model years available in the "Find a Car" tool.
  static Future<List<VehicleMenuItem>> getYears() {
    return _getMenu('$_baseUrl/menu/year');
  }

  /// Makes (brands) available for a given [year].
  static Future<List<VehicleMenuItem>> getMakes(String year) {
    return _getMenu('$_baseUrl/menu/make?year=$year');
  }

  /// Models available for a given [year] and [make].
  static Future<List<VehicleMenuItem>> getModels(String year, String make) {
    return _getMenu(
      '$_baseUrl/menu/model?year=$year&make=${Uri.encodeQueryComponent(make)}',
    );
  }

  /// A given year/make/model can map to more than one specific build
  /// (engine, transmission, drivetrain, etc). Each returned item's
  /// [VehicleMenuItem.value] is the vehicle id used by [getVehicleDetails].
  static Future<List<VehicleMenuItem>> getOptions(
    String year,
    String make,
    String model,
  ) {
    return _getMenu(
      '$_baseUrl/menu/options?year=$year'
      '&make=${Uri.encodeQueryComponent(make)}'
      '&model=${Uri.encodeQueryComponent(model)}',
    );
  }

  /// Fetches the full fuel-economy record for a specific vehicle id
  /// (obtained from [getOptions]).
  static Future<VehicleFuelEconomy> getVehicleDetails(String id) async {
    final uri = Uri.parse('$_baseUrl/$id');
    late final http.Response response;
    try {
      response = await http.get(uri, headers: _jsonHeaders);
    } catch (_) {
      throw VehicleApiException('Could not connect to fueleconomy.gov.');
    }
    if (response.statusCode != 200) {
      throw VehicleApiException(
        'Could not load vehicle data (${response.statusCode}).',
      );
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return VehicleFuelEconomy.fromJson(json);
    } catch (_) {
      throw VehicleApiException('Could not read the fuel economy data.');
    }
  }

  static Future<List<VehicleMenuItem>> _getMenu(String url) async {
    late final http.Response response;
    try {
      response = await http.get(Uri.parse(url), headers: _jsonHeaders);
    } catch (_) {
      throw VehicleApiException('Could not connect to fueleconomy.gov.');
    }
    if (response.statusCode != 200) {
      throw VehicleApiException(
        'Could not reach fueleconomy.gov (${response.statusCode}).',
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      final rawItems =
          decoded is Map<String, dynamic> ? decoded['menuItem'] : null;
      if (rawItems == null) return [];
      // The API returns a single object (not a list) when there's only
      // one matching item, so normalise that here.
      final list = rawItems is List ? rawItems : [rawItems];
      return list
          .whereType<Map<String, dynamic>>()
          .map(VehicleMenuItem.fromJson)
          .toList();
    } catch (_) {
      throw VehicleApiException(
        'Could not read the response from fueleconomy.gov.',
      );
    }
  }
}
