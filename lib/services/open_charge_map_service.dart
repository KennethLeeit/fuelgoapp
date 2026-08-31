import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'location_service.dart';

/// Fetches EV charging station data from Open Charge Map
/// (https://openchargemap.org) — a database purpose-built for exactly this
/// query shape (nearest charging stations within a radius), with
/// structured fields for connectors, power output, operator, and pricing.
///
/// This is the primary EV data source (see StationCacheService), with
/// OpenStreetMap kept as a fallback for areas Open Charge Map hasn't
/// covered yet. No API key is required for read access at moderate usage;
/// set [apiKey] if you register for one at
/// https://openchargemap.org/site/develop/api to raise the rate limit.
class OpenChargeMapService {
  static const _endpoint = 'https://api.openchargemap.io/v3/poi/';

  /// Optional — raises the anonymous rate limit if you have one. Free to
  /// register at https://openchargemap.org/site/loginprovider/register.
  static String? apiKey;

  static Future<List<EVCharger>> fetchNearby(AppLatLng center, {double radiusKm = 15, int limit = 40}) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'output': 'json',
      'latitude': '${center.lat}',
      'longitude': '${center.lng}',
      'distance': '$radiusKm',
      'distanceunit': 'KM',
      'maxresults': '$limit',
      'compact': 'true',
      'verbose': 'false',
      if (apiKey != null) 'key': apiKey!,
    });
    final res = await http.get(uri, headers: const {'User-Agent': 'FuelGo/1.0 (nearby station finder)'}).timeout(
      const Duration(seconds: 10),
    );
    if (res.statusCode != 200) {
      throw Exception('Open Charge Map returned ${res.statusCode}');
    }
    final List<dynamic> pois = json.decode(res.body);
    return _parse(pois, center);
  }

  /// Fetches specific chargers by their Open Charge Map POI id, regardless
  /// of location. Used to resolve favourited OCM-sourced chargers that
  /// aren't in the current nearby-search results.
  static Future<List<EVCharger>> fetchByIds(List<String> ids, {AppLatLng? reference}) async {
    if (ids.isEmpty) return const [];
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'output': 'json',
      'chargepointid': ids.join(','),
      'compact': 'true',
      'verbose': 'false',
      if (apiKey != null) 'key': apiKey!,
    });
    final res = await http.get(uri, headers: const {'User-Agent': 'FuelGo/1.0 (nearby station finder)'}).timeout(
      const Duration(seconds: 10),
    );
    if (res.statusCode != 200) {
      throw Exception('Open Charge Map returned ${res.statusCode}');
    }
    final List<dynamic> pois = json.decode(res.body);
    return _parse(pois, reference ?? const AppLatLng(0, 0));
  }

  static List<EVCharger> _parse(List<dynamic> pois, AppLatLng center) {
    final chargers = <EVCharger>[];

    for (final raw in pois) {
      try {
        final poi = raw as Map<String, dynamic>;
        final id = poi['ID'];
        if (id == null) continue;

        final addressInfo = poi['AddressInfo'] as Map<String, dynamic>?;
        if (addressInfo == null) continue;
        final lat = (addressInfo['Latitude'] as num?)?.toDouble();
        final lng = (addressInfo['Longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;

        final operatorInfo = poi['OperatorInfo'] as Map<String, dynamic>?;
        final operatorName = operatorInfo?['Title'] as String?;
        final name = (addressInfo['Title'] as String?)?.trim().isNotEmpty == true
            ? addressInfo['Title'] as String
            : (operatorName ?? 'EV Charger');

        final addressParts = [
          addressInfo['AddressLine1'],
          addressInfo['Town'],
          addressInfo['StateOrProvince'],
          addressInfo['Postcode'],
        ].where((p) => p != null && p.toString().trim().isNotEmpty).join(', ');

        final connections = (poi['Connections'] as List?) ?? const [];
        final connectors = <String>[];
        double maxPower = 0;
        for (final raw in connections) {
          final c = raw as Map<String, dynamic>;
          final type = c['ConnectionType'] as Map<String, dynamic>?;
          final typeTitle = type?['Title'] as String?;
          if (typeTitle != null && typeTitle.trim().isNotEmpty && !connectors.contains(typeTitle)) {
            connectors.add(typeTitle);
          }
          final power = (c['PowerKW'] as num?)?.toDouble();
          if (power != null && power > maxPower) maxPower = power;
        }

        final usageCost = (poi['UsageCost'] as String?)?.trim();

        bool? operational;
        final statusType = poi['StatusType'] as Map<String, dynamic>?;
        if (statusType != null && statusType['IsOperational'] != null) {
          operational = statusType['IsOperational'] as bool;
        }

        final charger = EVCharger(
          id: 'ocm/$id',
          name: name,
          operatorName: operatorName,
          address: addressParts.isNotEmpty ? addressParts : 'Address not available',
          latitude: lat,
          longitude: lng,
          connectors: connectors,
          maxPowerKw: maxPower > 0 ? maxPower.round() : null,
          usageCostRaw: (usageCost?.isNotEmpty ?? false) ? usageCost : null,
          operational: operational,
        );
        charger.distanceKm = double.parse(
          LocationService.distanceKm(center, AppLatLng(lat, lng)).toStringAsFixed(1),
        );
        chargers.add(charger);
      } catch (_) {
        // Skip malformed entries rather than failing the whole fetch.
        continue;
      }
    }

    chargers.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return chargers;
  }
}
