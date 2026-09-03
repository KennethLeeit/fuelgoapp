import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

import '../models/trip_models.dart';

class TripLocationException implements Exception {
  final String message;
  const TripLocationException(this.message);
  @override
  String toString() => message;
}

class TripLocationService {
  TripLocationService({
    FirebaseFunctions? functions,
    PublicTripLocationService? publicFallback,
  })  : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
        _publicFallback = publicFallback ?? PublicTripLocationService();

  final FirebaseFunctions _functions;
  final PublicTripLocationService _publicFallback;

  Future<List<TripPlace>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];
    try {
      final response = await _functions
          .httpsCallable('searchMalaysiaPlaces')
          .call<Map<String, dynamic>>({'query': trimmed});
      final raw = response.data['places'];
      if (raw is! List) return const [];
      final places = raw
          .whereType<Map>()
          .map((item) => TripPlace.fromMap(Map<String, dynamic>.from(item)))
          .where((place) => place.name.isNotEmpty)
          .toList();
      if (places.isEmpty) {
        return _publicFallback.searchPlaces(trimmed);
      }
      return places;
    } on FirebaseFunctionsException catch (error) {
      if (_canUseFallback(error)) {
        return _publicFallback.searchPlaces(trimmed);
      }
      throw TripLocationException(_friendlyMessage(error));
    } on TripLocationException {
      rethrow;
    } catch (_) {
      return _publicFallback.searchPlaces(trimmed);
    }
  }

  Future<TripPlace> reverseGeocode(double latitude, double longitude) async {
    try {
      final response = await _functions
          .httpsCallable('reverseMalaysiaPlace')
          .call<Map<String, dynamic>>({
        'latitude': latitude,
        'longitude': longitude,
      });
      return TripPlace.fromMap(response.data);
    } on FirebaseFunctionsException catch (error) {
      if (_canUseFallback(error)) {
        return _publicFallback.reverseGeocode(latitude, longitude);
      }
      throw TripLocationException(_friendlyMessage(error));
    } on TripLocationException {
      rethrow;
    } catch (_) {
      return _publicFallback.reverseGeocode(latitude, longitude);
    }
  }

  Future<double> drivingDistanceKm(TripPlace from, TripPlace to) async {
    return (await drivingRoute(from, to)).distanceKm;
  }

  Future<DrivingRoute> drivingRoute(TripPlace from, TripPlace to) async {
    try {
      final response = await _functions
          .httpsCallable('calculateMalaysiaRoute')
          .call<Map<String, dynamic>>({
        'from': {
          'latitude': from.latitude,
          'longitude': from.longitude,
        },
        'to': {
          'latitude': to.latitude,
          'longitude': to.longitude,
        },
      });
      final route = DrivingRoute.fromMap(response.data);
      if (!route.distanceKm.isFinite || route.distanceKm <= 0) {
        throw const TripLocationException('No driving route was found.');
      }
      if (!route.hasGeometry) {
        return _publicFallback.drivingRoute(from, to);
      }
      return route;
    } on FirebaseFunctionsException catch (error) {
      if (_canUseFallback(error)) {
        return _publicFallback.drivingRoute(from, to);
      }
      throw TripLocationException(_friendlyMessage(error));
    } on TripLocationException {
      rethrow;
    } catch (_) {
      return _publicFallback.drivingRoute(from, to);
    }
  }

  bool _canUseFallback(FirebaseFunctionsException error) =>
      error.code != 'unauthenticated' && error.code != 'invalid-argument';

  String _friendlyMessage(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'unauthenticated':
        return 'You need to be signed in to search and calculate routes.';
      case 'invalid-argument':
        return error.message ?? 'The selected locations are invalid.';
      case 'not-found':
        return error.message ??
            'No matching location or driving route was found.';
      case 'resource-exhausted':
        return 'The routing service is busy. Please try again shortly.';
      case 'deadline-exceeded':
      case 'unavailable':
        return 'The routing service is temporarily unavailable. Please try again.';
      default:
        return error.message ?? 'Could not complete the location request.';
    }
  }
}

/// No-key fallback for development and light traffic when the protected
/// Firebase/OpenRouteService backend has not been deployed yet. Photon is
/// used for OSM place matching and OSRM supplies driving distance.
class PublicTripLocationService {
  PublicTripLocationService({http.Client? client})
      : _client = client ?? http.Client();

  static const _photonHost = 'photon.komoot.io';
  static const _osrmHost = 'router.project-osrm.org';

  final http.Client _client;

  Future<List<TripPlace>> searchPlaces(String query) async {
    final uri = Uri.https(_photonHost, '/api', {
      'q': query.trim(),
      'limit': '8',
      'lang': 'en',
      'bbox': '99.5,0.8,119.5,7.5',
    });
    final data = await _getJson(
      uri,
      failureMessage: 'Could not search locations.',
    );
    final features = data['features'];
    if (features is! List) return const [];
    final places = <TripPlace>[];
    final seen = <String>{};
    for (final feature in features.whereType<Map>()) {
      final place = _placeFromPhoton(Map<String, dynamic>.from(feature));
      if (place == null) continue;
      final key =
          '${place.name.toLowerCase()}:${place.latitude}:${place.longitude}';
      if (seen.add(key)) places.add(place);
    }
    return places;
  }

  Future<TripPlace> reverseGeocode(double latitude, double longitude) async {
    _validateMalaysiaCoordinate(latitude, longitude);
    final uri = Uri.https(_photonHost, '/reverse', {
      'lat': '$latitude',
      'lon': '$longitude',
      'limit': '1',
      'lang': 'en',
      'radius': '10',
    });
    final data = await _getJson(
      uri,
      failureMessage: 'Your location could not be identified.',
    );
    final features = data['features'];
    if (features is List) {
      for (final feature in features.whereType<Map>()) {
        final place = _placeFromPhoton(Map<String, dynamic>.from(feature));
        if (place != null) return place;
      }
    }
    throw const TripLocationException(
        'Your location could not be identified in Malaysia.');
  }

  Future<double> drivingDistanceKm(TripPlace from, TripPlace to) async {
    return (await drivingRoute(from, to)).distanceKm;
  }

  Future<DrivingRoute> drivingRoute(TripPlace from, TripPlace to) async {
    _validateMalaysiaCoordinate(from.latitude, from.longitude);
    _validateMalaysiaCoordinate(to.latitude, to.longitude);
    final coordinatePair =
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.https(
      _osrmHost,
      '/route/v1/driving/$coordinatePair',
      const {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
        'alternatives': 'false',
      },
    );
    final data = await _getJson(
      uri,
      failureMessage: 'Could not calculate the driving route.',
      timeout: const Duration(seconds: 15),
    );
    final routes = data['routes'];
    final first = routes is List && routes.isNotEmpty ? routes.first : null;
    final distance = first is Map ? first['distance'] : null;
    final duration = first is Map ? first['duration'] : null;
    final geometryData = first is Map ? first['geometry'] : null;
    final routeCoordinates =
        geometryData is Map ? geometryData['coordinates'] : null;
    final metres = distance is num ? distance.toDouble() : null;
    if (data['code'] != 'Ok' || metres == null || metres <= 0) {
      throw const TripLocationException(
          'No driving route was found for those locations.');
    }
    final points = <TripPlace>[];
    if (routeCoordinates is List) {
      for (final raw in routeCoordinates.whereType<List>()) {
        if (raw.length < 2) continue;
        final longitude = _number(raw[0]);
        final latitude = _number(raw[1]);
        if (latitude == null || longitude == null) continue;
        points.add(TripPlace(
          name: '',
          address: '',
          latitude: latitude,
          longitude: longitude,
        ));
      }
    }
    if (points.length < 2) {
      throw const TripLocationException(
          'The driving route geometry is unavailable.');
    }
    return DrivingRoute(
      distanceKm: metres / 1000,
      durationSeconds: duration is num ? duration.toDouble() : null,
      geometry: points,
    );
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required String failureMessage,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      // Keep this a simple CORS-safe GET so the same fallback works on
      // Android, iOS and Flutter Web without a preflight-only header.
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode == 429) {
        throw const TripLocationException(
            'The public location service is busy. Try again shortly.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TripLocationException('$failureMessage Please try again.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on TripLocationException {
      rethrow;
    } on TimeoutException {
      throw TripLocationException('$failureMessage The request timed out.');
    } catch (_) {
      throw TripLocationException(
          '$failureMessage Check your connection and try again.');
    }
  }

  TripPlace? _placeFromPhoton(Map<String, dynamic> feature) {
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    if (properties is! Map || geometry is! Map) return null;
    final values = Map<String, dynamic>.from(properties);
    if ((values['countrycode'] ?? '').toString().toUpperCase() != 'MY') {
      return null;
    }
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final longitude = _number(coordinates[0]);
    final latitude = _number(coordinates[1]);
    if (latitude == null || longitude == null) return null;
    if (!_insideMalaysia(latitude, longitude)) return null;
    final name = (values['name'] ?? values['city'] ?? values['state'] ?? '')
        .toString()
        .trim();
    if (name.isEmpty) return null;
    final addressParts = <dynamic>[
      name,
      values['street'],
      values['district'],
      values['city'],
      values['county'],
      values['state'],
      values['postcode'],
      values['country'],
    ]
        .where((value) => value != null && '$value'.trim().isNotEmpty)
        .map((value) => '$value'.trim())
        .toSet()
        .toList();
    return TripPlace(
      name: name,
      address: addressParts.join(', '),
      latitude: latitude,
      longitude: longitude,
    );
  }

  double? _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value');

  bool _insideMalaysia(double latitude, double longitude) =>
      latitude >= .8 &&
      latitude <= 7.5 &&
      longitude >= 99.5 &&
      longitude <= 119.5;

  void _validateMalaysiaCoordinate(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        !_insideMalaysia(latitude, longitude)) {
      throw const TripLocationException('Select a location within Malaysia.');
    }
  }
}
