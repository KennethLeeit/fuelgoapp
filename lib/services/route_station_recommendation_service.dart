import 'dart:math' as math;

import '../models/models.dart';
import '../models/trip_models.dart';
import 'location_service.dart';
import 'mygeomap_fuel_service.dart';
import 'open_charge_map_service.dart';
import 'osm_ev_charger_service.dart';
import 'osm_fuel_service.dart';
import 'station_cache_service.dart';

class AlongRouteRecommendation<T> {
  final T place;
  final double distanceFromRouteKm;
  final double distanceFromStartKm;
  final double distanceAheadKm;
  final String reason;
  final bool recommended;

  const AlongRouteRecommendation({
    required this.place,
    required this.distanceFromRouteKm,
    required this.distanceFromStartKm,
    required this.distanceAheadKm,
    required this.reason,
    required this.recommended,
  });

  AlongRouteRecommendation<T> asRecommended() => AlongRouteRecommendation(
        place: place,
        distanceFromRouteKm: distanceFromRouteKm,
        distanceFromStartKm: distanceFromStartKm,
        distanceAheadKm: distanceAheadKm,
        reason: reason,
        recommended: true,
      );
}

class RouteStationRecommendationService {
  static const double normalCorridorKm = 5;
  static const double wideCorridorKm = 10;
  static const double endpointRadiusKm = 12;
  static const double _sampleSpacingKm = 50;
  static const double _fetchRadiusKm = 30;
  static const int _fetchLimit = 80;

  static Future<List<FuelStation>> fetchFuelCandidates(
      DrivingRoute route) async {
    final batches = await _fetchInBatches(
      sampleCenters(route),
      (center) async {
        try {
          final result = await MyGeoMapFuelService.fetchNearby(
            center,
            radiusKm: _fetchRadiusKm,
            limit: _fetchLimit,
            resolveAddresses: false,
          );
          if (result.isNotEmpty) return result;
        } catch (_) {}
        try {
          return await OsmFuelService.fetchNearby(
            center,
            radiusKm: _fetchRadiusKm,
            limit: _fetchLimit,
            resolveAddresses: false,
          );
        } catch (_) {
          return const <FuelStation>[];
        }
      },
    );
    return _deduplicateFuel(batches.expand((batch) => batch));
  }

  static Future<List<EVCharger>> fetchEvCandidates(
    DrivingRoute route, {
    bool forceRefreshOrigin = false,
  }) async {
    final centers = sampleCenters(route);
    if (centers.isEmpty) return const [];

    var originChargers = const <EVCharger>[];
    try {
      originChargers = await StationCacheService.instance.ev(
        centers.first,
        radiusKm: 12,
        limit: 40,
        forceRefresh: forceRefreshOrigin,
      );
    } catch (_) {}
    final batches = await _fetchInBatches(
      centers,
      (center) async {
        var openChargeMap = const <EVCharger>[];
        if (OpenChargeMapService.apiKey != null) {
          try {
            openChargeMap = await OpenChargeMapService.fetchNearby(
              center,
              radiusKm: _fetchRadiusKm,
              limit: _fetchLimit,
            );
          } catch (_) {}
        }
        final isEndpoint =
            LocationService.distanceKm(center, centers.first) < .1 ||
                LocationService.distanceKm(center, centers.last) < .1;
        if (openChargeMap.isNotEmpty && !isEndpoint) return openChargeMap;
        try {
          final osm = await OsmEvChargerService.fetchNearby(
            center,
            radiusKm: _fetchRadiusKm,
            limit: _fetchLimit,
          );
          return [...openChargeMap, ...osm];
        } catch (_) {
          return openChargeMap;
        }
      },
    );
    return _deduplicateEv([
      ...originChargers,
      ...batches.expand((batch) => batch),
    ]);
  }

  static List<AppLatLng> sampleCenters(DrivingRoute route) {
    if (!route.hasGeometry) return const [];
    final result = <AppLatLng>[];
    var sinceLast = _sampleSpacingKm;
    TripPlace? previous;
    for (final point in route.geometry) {
      if (previous != null) {
        sinceLast += LocationService.distanceKm(
          AppLatLng(previous.latitude, previous.longitude),
          AppLatLng(point.latitude, point.longitude),
        );
      }
      if (result.isEmpty || sinceLast >= _sampleSpacingKm) {
        result.add(AppLatLng(point.latitude, point.longitude));
        sinceLast = 0;
      }
      previous = point;
    }
    final last = route.geometry.last;
    final lastCoordinate = AppLatLng(last.latitude, last.longitude);
    if (LocationService.distanceKm(result.last, lastCoordinate) > 1) {
      result.add(lastCoordinate);
    }
    return result;
  }

  static List<AlongRouteRecommendation<FuelStation>> rankFuel(
    DrivingRoute route,
    Iterable<FuelStation> stations, {
    String? selectedFuel,
    double corridorKm = normalCorridorKm,
  }) {
    final fuel = _normaliseFuel(selectedFuel);
    final ranked = <AlongRouteRecommendation<FuelStation>>[];
    for (final station in _deduplicateFuel(stations)) {
      final metric =
          _metricFor(route, station.latitude, station.longitude, corridorKm);
      if (metric == null) continue;
      final verifiedFuel = fuel != null &&
          station.fuelTypes.any((value) => _normaliseFuel(value) == fuel);
      final proximityText = metric.endpointLabel ?? 'close to route';
      final reason = verifiedFuel
          ? '$selectedFuel listed · $proximityText'
          : station.open24Hours == true
              ? 'Open 24 hours · $proximityText'
              : metric.endpointLabel ?? 'Close to your route';
      ranked.add(AlongRouteRecommendation(
        place: station,
        distanceFromRouteKm: metric.distanceFromRouteKm,
        distanceFromStartKm: _distanceFromStart(
          route,
          station.latitude,
          station.longitude,
        ),
        distanceAheadKm: metric.distanceAheadKm,
        reason: reason,
        recommended: false,
      ));
    }
    ranked.sort((a, b) {
      final aNearStart = a.distanceFromStartKm <= endpointRadiusKm;
      final bNearStart = b.distanceFromStartKm <= endpointRadiusKm;
      if (aNearStart != bNearStart) return aNearStart ? -1 : 1;
      if (aNearStart && bNearStart) {
        final startDistance = _proximityBucket(a.distanceFromStartKm)
            .compareTo(_proximityBucket(b.distanceFromStartKm));
        if (startDistance != 0) return startDistance;
      }
      final proximity = _proximityBucket(a.distanceFromRouteKm)
          .compareTo(_proximityBucket(b.distanceFromRouteKm));
      if (proximity != 0) return proximity;
      final aFuel = fuel != null &&
          a.place.fuelTypes.any((value) => _normaliseFuel(value) == fuel);
      final bFuel = fuel != null &&
          b.place.fuelTypes.any((value) => _normaliseFuel(value) == fuel);
      if (aFuel != bFuel) return aFuel ? -1 : 1;
      if (a.place.open24Hours != b.place.open24Hours) {
        return a.place.open24Hours == true ? -1 : 1;
      }
      final ahead = a.distanceAheadKm.compareTo(b.distanceAheadKm);
      if (ahead != 0) return ahead;
      return a.place.id.compareTo(b.place.id);
    });
    if (ranked.isNotEmpty) ranked[0] = ranked[0].asRecommended();
    return ranked;
  }

  static List<AlongRouteRecommendation<EVCharger>> rankEv(
    DrivingRoute route,
    Iterable<EVCharger> chargers, {
    String? preferredProvider,
    double corridorKm = normalCorridorKm,
  }) {
    final preferred = preferredProvider?.trim().toLowerCase();
    final ranked = <AlongRouteRecommendation<EVCharger>>[];
    for (final charger in _deduplicateEv(chargers)) {
      if (charger.operational == false) continue;
      final metric =
          _metricFor(route, charger.latitude, charger.longitude, corridorKm);
      if (metric == null) continue;
      final providerMatch = preferred?.isNotEmpty == true &&
          (charger.operatorName ?? '').toLowerCase().contains(preferred!);
      final proximityText = metric.endpointLabel ?? 'close to route';
      final reason = providerMatch
          ? 'Preferred provider · $proximityText'
          : (charger.maxPowerKw ?? 0) >= 50
              ? 'Fast charger · $proximityText'
              : metric.endpointLabel ?? 'Close to your route';
      ranked.add(AlongRouteRecommendation(
        place: charger,
        distanceFromRouteKm: metric.distanceFromRouteKm,
        distanceFromStartKm: _distanceFromStart(
          route,
          charger.latitude,
          charger.longitude,
        ),
        distanceAheadKm: metric.distanceAheadKm,
        reason: reason,
        recommended: false,
      ));
    }
    ranked.sort((a, b) {
      final aNearStart = a.distanceFromStartKm <= endpointRadiusKm;
      final bNearStart = b.distanceFromStartKm <= endpointRadiusKm;
      if (aNearStart != bNearStart) return aNearStart ? -1 : 1;
      if (aNearStart && bNearStart) {
        final startDistance = _proximityBucket(a.distanceFromStartKm)
            .compareTo(_proximityBucket(b.distanceFromStartKm));
        if (startDistance != 0) return startDistance;
      }
      final proximity = _proximityBucket(a.distanceFromRouteKm)
          .compareTo(_proximityBucket(b.distanceFromRouteKm));
      if (proximity != 0) return proximity;
      final aProvider = preferred?.isNotEmpty == true &&
          (a.place.operatorName ?? '').toLowerCase().contains(preferred!);
      final bProvider = preferred?.isNotEmpty == true &&
          (b.place.operatorName ?? '').toLowerCase().contains(preferred!);
      if (aProvider != bProvider) return aProvider ? -1 : 1;
      final power =
          (b.place.maxPowerKw ?? 0).compareTo(a.place.maxPowerKw ?? 0);
      if (power != 0) return power;
      final ahead = a.distanceAheadKm.compareTo(b.distanceAheadKm);
      if (ahead != 0) return ahead;
      return a.place.id.compareTo(b.place.id);
    });
    if (ranked.isNotEmpty) ranked[0] = ranked[0].asRecommended();
    return ranked;
  }

  static double _distanceFromStart(
    DrivingRoute route,
    double latitude,
    double longitude,
  ) {
    final start = route.geometry.first;
    return LocationService.distanceKm(
      AppLatLng(latitude, longitude),
      AppLatLng(start.latitude, start.longitude),
    );
  }

  static _RouteMetric? _metricFor(
    DrivingRoute route,
    double latitude,
    double longitude,
    double corridorKm,
  ) {
    if (!latitude.isFinite || !longitude.isFinite || !route.hasGeometry) {
      return null;
    }
    var bestDistance = double.infinity;
    var bestAhead = 0.0;
    var accumulated = 0.0;
    for (var index = 1; index < route.geometry.length; index++) {
      final start = route.geometry[index - 1];
      final end = route.geometry[index];
      final segmentKm = LocationService.distanceKm(
        AppLatLng(start.latitude, start.longitude),
        AppLatLng(end.latitude, end.longitude),
      );
      if (segmentKm == 0) continue;
      final projection = _project(
        latitude,
        longitude,
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );
      if (projection.distanceKm < bestDistance) {
        bestDistance = projection.distanceKm;
        bestAhead = accumulated + segmentKm * projection.fraction;
      }
      accumulated += segmentKm;
    }
    if (bestDistance <= corridorKm) {
      return _RouteMetric(bestDistance, bestAhead);
    }

    final first = route.geometry.first;
    final last = route.geometry.last;
    final fromStart = LocationService.distanceKm(
      AppLatLng(latitude, longitude),
      AppLatLng(first.latitude, first.longitude),
    );
    final fromEnd = LocationService.distanceKm(
      AppLatLng(latitude, longitude),
      AppLatLng(last.latitude, last.longitude),
    );
    if (fromStart <= endpointRadiusKm && fromStart <= fromEnd) {
      return _RouteMetric(bestDistance, 0, endpointLabel: 'Near your start');
    }
    if (fromEnd <= endpointRadiusKm) {
      return _RouteMetric(bestDistance, accumulated,
          endpointLabel: 'Near your destination');
    }
    return null;
  }

  static _Projection _project(double pointLat, double pointLon, double startLat,
      double startLon, double endLat, double endLon) {
    const kmPerDegreeLat = 110.574;
    final meanLat = (pointLat + startLat + endLat) / 3;
    final kmPerDegreeLon =
        111.320 * math.cos(meanLat * math.pi / 180).abs().clamp(.2, 1);
    final px = (pointLon - startLon) * kmPerDegreeLon;
    final py = (pointLat - startLat) * kmPerDegreeLat;
    final ex = (endLon - startLon) * kmPerDegreeLon;
    final ey = (endLat - startLat) * kmPerDegreeLat;
    final lengthSquared = ex * ex + ey * ey;
    final fraction = lengthSquared == 0
        ? 0.0
        : ((px * ex + py * ey) / lengthSquared).clamp(0.0, 1.0);
    final dx = px - ex * fraction;
    final dy = py - ey * fraction;
    return _Projection(math.sqrt(dx * dx + dy * dy), fraction);
  }

  static String? _normaliseFuel(String? value) {
    final text = value?.toLowerCase() ?? '';
    if (text.contains('diesel')) return 'diesel';
    if (text.contains('97')) return 'ron97';
    if (text.contains('95')) return 'ron95';
    return null;
  }

  static int _proximityBucket(double kilometres) => (kilometres * 100).round();

  static List<FuelStation> _deduplicateFuel(Iterable<FuelStation> values) {
    final result = <FuelStation>[];
    final ids = <String>{};
    for (final station in values) {
      if (!ids.add(station.id)) continue;
      final duplicate = result.any((other) =>
          _sameName(other.name, station.name) &&
          LocationService.distanceKm(
                AppLatLng(other.latitude, other.longitude),
                AppLatLng(station.latitude, station.longitude),
              ) <
              .15);
      if (!duplicate) result.add(station);
    }
    return result;
  }

  static List<EVCharger> _deduplicateEv(Iterable<EVCharger> values) {
    final result = <EVCharger>[];
    final ids = <String>{};
    for (final charger in values) {
      if (!ids.add(charger.id)) continue;
      final duplicate = result.any((other) =>
          _sameName(other.name, charger.name) &&
          LocationService.distanceKm(
                AppLatLng(other.latitude, other.longitude),
                AppLatLng(charger.latitude, charger.longitude),
              ) <
              .15);
      if (!duplicate) result.add(charger);
    }
    return result;
  }

  static bool _sameName(String a, String b) =>
      a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') ==
      b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Future<List<List<T>>> _fetchInBatches<T>(
    List<AppLatLng> centers,
    Future<List<T>> Function(AppLatLng center) fetch,
  ) async {
    final results = <List<T>>[];
    for (var index = 0; index < centers.length; index += 3) {
      final end = math.min(index + 3, centers.length);
      results.addAll(await Future.wait(centers.sublist(index, end).map(fetch)));
    }
    return results;
  }
}

class _RouteMetric {
  final double distanceFromRouteKm;
  final double distanceAheadKm;
  final String? endpointLabel;
  const _RouteMetric(
    this.distanceFromRouteKm,
    this.distanceAheadKm, {
    this.endpointLabel,
  });
}

class _Projection {
  final double distanceKm;
  final double fraction;
  const _Projection(this.distanceKm, this.fraction);
}
