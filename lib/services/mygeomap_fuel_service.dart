import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'location_service.dart';
import 'mygeomap_reverse_geocoding_service.dart';

/// Loads Malaysian petrol stations from the government's MyGeoMap ArcGIS
/// service. The endpoint is free, keyless, and supports Flutter web CORS.
class MyGeoMapFuelService {
  static const _endpoint =
      'https://service.mygeomap.gov.my/arcgis/rest/services/'
      'Transportation_services/1MM_Template_Transportation_Services/'
      'MapServer/5/query';

  static const _fields = [
    'here.SDE.AutoSvc_1.OBJECTID',
    'here.SDE.AutoSvc_1.POI_NAME',
    'here.SDE.AutoSvc_1.OPEN_24',
    'here.SDE.AutoSvc_1.DIESEL',
    'here.SDE.AutoSvc_1.ACT_ADDR',
    'here.SDE.AutoSvc_1.ACT_ST_NAM',
    'here.SDE.AutoSvc_1.ACT_ADMIN',
    'here.SDE.AutoSvc_1.ACT_POSTAL',
    'here.SDE.AutoSvc_1.Full_Address',
    'here.SDE.AutoSvc_1.POI_Name_StreetNam_Postcode',
    'here.SDE.AutoSvc_1.Street_Name',
    'here.SDE.AutoSvc_1.Left_Builtup_Name',
    'here.SDE.AutoSvc_1.Left_Order1_Name',
    'here.SDE.AutoSvc_1.Left_Postal_Code',
    'here.SDE.AutoSvc_1.Right_Builtup_Name',
    'here.SDE.AutoSvc_1.Right_Order1_Name',
    'here.SDE.AutoSvc_1.Right_Postal_Code',
  ];

  static Future<List<FuelStation>> fetchNearby(
    AppLatLng center, {
    double radiusKm = 15,
    int limit = 40,
  }) async {
    final latDelta = radiusKm / 110.574;
    final longitudeScale =
        111.320 * math.cos(center.lat * math.pi / 180).abs().clamp(0.2, 1.0);
    final lngDelta = radiusKm / longitudeScale;
    final envelope = [
      center.lng - lngDelta,
      center.lat - latDelta,
      center.lng + lngDelta,
      center.lat + latDelta,
    ].join(',');

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'f': 'geojson',
      'where': '1=1',
      'geometry': envelope,
      'geometryType': 'esriGeometryEnvelope',
      'inSR': '4326',
      'outSR': '4326',
      'outFields': _fields.join(','),
      'returnGeometry': 'true',
      'resultRecordCount': '500',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('MyGeoMap returned ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['error'] != null) {
      throw Exception('MyGeoMap query failed');
    }

    final stations = <FuelStation>[];
    for (final raw in decoded['features'] as List<dynamic>? ?? const []) {
      try {
        final feature = raw as Map<String, dynamic>;
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        final coordinates = geometry?['coordinates'] as List<dynamic>?;
        if (coordinates == null || coordinates.length < 2) continue;
        final lng = (coordinates[0] as num).toDouble();
        final lat = (coordinates[1] as num).toDouble();
        final distance =
            LocationService.distanceKm(center, AppLatLng(lat, lng));
        if (distance > radiusKm) continue;

        final properties = Map<String, dynamic>.from(
          feature['properties'] as Map? ?? const {},
        );
        final rawName = _value(properties, 'POI_NAME');
        final brand = _normaliseBrand(rawName);
        final objectId =
            _value(properties, 'OBJECTID') ?? feature['id'].toString();
        final open24Raw = _value(properties, 'OPEN_24')?.toUpperCase();
        final dieselRaw = _value(properties, 'DIESEL')?.toUpperCase();

        stations.add(FuelStation(
          id: 'mygeomap/$objectId',
          name: brand ?? rawName ?? 'Fuel station',
          brand: brand,
          address: _address(properties, rawName),
          latitude: lat,
          longitude: lng,
          distanceKm: double.parse(distance.toStringAsFixed(1)),
          open24Hours: open24Raw == 'Y' || open24Raw == 'YES'
              ? true
              : open24Raw == 'N' || open24Raw == 'NO'
                  ? false
                  : null,
          openingHoursRaw:
              open24Raw == 'Y' || open24Raw == 'YES' ? '24/7' : null,
          fuelTypes: dieselRaw == 'Y' || dieselRaw == 'YES'
              ? const ['Diesel']
              : const [],
          brandColor: colorForName(brand ?? rawName),
        ));
      } catch (error) {
        debugPrint('[MyGeoMapFuelService] Ignored invalid feature: $error');
      }
    }

    stations.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    final nearby = stations.take(limit).toList(growable: false);
    final resolved =
        await MyGeoMapReverseGeocodingService.resolveMissing(nearby);
    return nearby.map((station) {
      final address = resolved[station.id];
      return address == null ? station : _withAddress(station, address);
    }).toList(growable: false);
  }

  static String? _value(Map<String, dynamic> values, String field) {
    for (final entry in values.entries) {
      if (entry.key.toUpperCase().endsWith('.${field.toUpperCase()}')) {
        final value = entry.value?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  static String _address(Map<String, dynamic> values, String? stationName) {
    final fullAddress = _value(values, 'Full_Address');
    if (fullAddress != null &&
        fullAddress.toLowerCase() != stationName?.toLowerCase()) {
      return fullAddress;
    }

    final parts = [
      _value(values, 'ACT_ADDR'),
      _value(values, 'ACT_ST_NAM'),
      _value(values, 'Street_Name'),
      _value(values, 'Left_Builtup_Name') ??
          _value(values, 'Right_Builtup_Name'),
      _value(values, 'ACT_ADMIN'),
      _value(values, 'Left_Order1_Name') ?? _value(values, 'Right_Order1_Name'),
      _value(values, 'ACT_POSTAL'),
      _value(values, 'Left_Postal_Code') ?? _value(values, 'Right_Postal_Code'),
    ].whereType<String>().toSet().toList();
    if (parts.isNotEmpty) return parts.join(', ');

    final combined = _value(values, 'POI_Name_StreetNam_Postcode');
    if (combined != null) {
      final combinedParts = combined
          .split(',')
          .map((part) => part.trim())
          .where((part) =>
              part.isNotEmpty &&
              part.toLowerCase() != stationName?.toLowerCase())
          .toList();
      if (combinedParts.isNotEmpty) return combinedParts.join(', ');
    }
    return 'Address not provided';
  }

  static FuelStation _withAddress(FuelStation station, String address) {
    return FuelStation(
      id: station.id,
      name: station.name,
      brand: station.brand,
      address: address,
      latitude: station.latitude,
      longitude: station.longitude,
      distanceKm: station.distanceKm,
      open24Hours: station.open24Hours,
      openingHoursRaw: station.openingHoursRaw,
      fuelTypes: station.fuelTypes,
      services: station.services,
      brandColor: station.brandColor,
      imageUrl: station.imageUrl,
      website: station.website,
    );
  }

  static String? _normaliseBrand(String? value) {
    if (value == null) return null;
    final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.contains('petronas')) return 'Petronas';
    if (compact.contains('shell')) return 'Shell';
    if (compact.contains('bhpetrol') || compact == 'bhp') return 'BHPetrol';
    if (compact.contains('petron')) return 'Petron';
    if (compact.contains('caltex') || compact.contains('chevron')) {
      return 'Caltex';
    }
    return value;
  }
}
