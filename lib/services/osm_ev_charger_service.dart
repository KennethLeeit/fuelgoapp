import 'dart:convert';
import '../models/models.dart';

/// Fetches real EV charging station locations from OpenStreetMap via the
/// free, keyless Overpass API — same source and same reliability pattern
/// (multi-mirror fallback) as [OsmFuelService]. No signup, no API key, no
/// billing, ever.
/// OSM tag reference: https://wiki.openstreetmap.org/wiki/Tag:amenity%3Dcharging_station
class OsmEvChargerService {
  static const List<String> _endpoints = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://overpass.openstreetmap.ru/api/interpreter',
  ];

  // OSM tags for the connector types we recognize, mapped to a friendly label.
  static const Map<String, String> _connectorTags = {
    'socket:type2': 'Type 2',
    'socket:type2_combo': 'CCS2',
    'socket:chademo': 'CHAdeMO',
    'socket:tesla_supercharger': 'Tesla Supercharger',
    'socket:tesla_standard': 'Tesla',
    'socket:schuko': 'Schuko',
    'socket:type1': 'Type 1',
    'socket:type1_combo': 'CCS1',
  };


}
