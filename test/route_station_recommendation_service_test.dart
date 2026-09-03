import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/models/models.dart';
import 'package:fuelgo_app/models/trip_models.dart';
import 'package:fuelgo_app/services/route_station_recommendation_service.dart';

void main() {
  const route = DrivingRoute(
    distanceKm: 111,
    durationSeconds: 3600,
    geometry: [
      TripPlace(name: '', address: '', latitude: 3, longitude: 101),
      TripPlace(name: '', address: '', latitude: 3, longitude: 102),
    ],
  );

  FuelStation station(String id, double latitude, double longitude,
          {List<String> fuels = const []}) =>
      FuelStation(
        id: id,
        name: id,
        address: 'Address',
        latitude: latitude,
        longitude: longitude,
        fuelTypes: fuels,
        brandColor: Colors.orange,
      );

  test('keeps stations inside corridor and reports distance ahead', () {
    final ranked = RouteStationRecommendationService.rankFuel(
      route,
      [
        station('on-route', 3.01, 101.5),
        station('outside', 3.2, 101.5),
      ],
      corridorKm: 5,
    );

    expect(ranked, hasLength(1));
    expect(ranked.single.place.id, 'on-route');
    expect(ranked.single.distanceFromRouteKm, closeTo(1.1, .15));
    expect(ranked.single.distanceAheadKm, closeTo(55.5, 1));
    expect(ranked.single.recommended, isTrue);
  });

  test('uses verified fuel as tie-breaker without overriding proximity', () {
    final ranked = RouteStationRecommendationService.rankFuel(
      route,
      [
        station('unknown', 3.005, 101.5),
        station('verified', 3.005, 101.51, fuels: const ['RON97']),
        station('far-verified', 3.03, 101.52, fuels: const ['RON97']),
      ],
      selectedFuel: 'RON97',
    );

    expect(ranked.first.place.id, 'verified');
    expect(ranked.last.place.id, 'far-verified');
  });

  test('route sampling always includes origin and destination', () {
    final centers = RouteStationRecommendationService.sampleCenters(route);
    expect(centers.first.lng, 101);
    expect(centers.last.lng, 102);
  });

  test('keeps a nearby charger at the route start outside narrow corridor', () {
    final ranked = RouteStationRecommendationService.rankEv(
      route,
      [
        EVCharger(
          id: 'ev-near-start',
          name: 'EVGuru',
          address: 'Near origin',
          latitude: 3.08,
          longitude: 100.99,
        ),
      ],
      corridorKm: 5,
    );

    expect(ranked, hasLength(1));
    expect(ranked.single.reason, 'Near your start');
    expect(ranked.single.distanceFromRouteKm, greaterThan(5));
  });

  test('EV recommendation does not depend on API result order', () {
    final chargers = [
      EVCharger(
        id: 'later-fast',
        name: 'BMW Charging',
        address: 'Later on route',
        latitude: 3.0004,
        longitude: 101.8,
        maxPowerKw: 100,
      ),
      EVCharger(
        id: 'earlier-near',
        name: 'EVGuru',
        address: 'Near route start',
        latitude: 3.0001,
        longitude: 101.1,
        maxPowerKw: 22,
      ),
    ];

    final forward = RouteStationRecommendationService.rankEv(route, chargers);
    final reversed = RouteStationRecommendationService.rankEv(
      route,
      chargers.reversed,
    );

    expect(forward.first.place.id, 'earlier-near');
    expect(reversed.first.place.id, forward.first.place.id);
  });

  test('nearby charger at route start stays ahead of route-line tie-breakers',
      () {
    final ranked = RouteStationRecommendationService.rankEv(route, [
      EVCharger(
        id: 'bmw',
        name: 'BMW Charging',
        address: 'Exactly on route but farther from start',
        latitude: 3,
        longitude: 101.04,
        maxPowerKw: 150,
      ),
      EVCharger(
        id: 'evguru',
        name: 'EVGuru',
        address: 'Closest to current location',
        latitude: 3.001,
        longitude: 101.005,
        maxPowerKw: 22,
      ),
    ]);

    expect(ranked.first.place.id, 'evguru');
  });

  test('fuel recommendation follows a changed route origin', () {
    final ranked = RouteStationRecommendationService.rankFuel(route, [
      station('near-selected-origin', 3.01, 101.02),
      station('farther-on-shared-route', 3, 101.7),
    ]);

    expect(ranked.first.place.id, 'near-selected-origin');
  });
}
