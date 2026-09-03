import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/models/trip_models.dart';
import 'package:fuelgo_app/services/trip_location_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Photon search returns matching Malaysian dropdown places only',
      () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'photon.komoot.io');
      expect(request.url.path, '/api');
      expect(request.url.queryParameters['q'], 'KLCC');
      return http.Response(
        jsonEncode({
          'features': [
            {
              'geometry': {
                'coordinates': [101.7123, 3.1579],
              },
              'properties': {
                'countrycode': 'MY',
                'name': 'KLCC',
                'city': 'Kuala Lumpur',
                'country': 'Malaysia',
              },
            },
            {
              'geometry': {
                'coordinates': [103.8198, 1.3521],
              },
              'properties': {
                'countrycode': 'SG',
                'name': 'Singapore',
              },
            },
          ],
        }),
        200,
      );
    });

    final service = PublicTripLocationService(client: client);
    final places = await service.searchPlaces('KLCC');

    expect(places, hasLength(1));
    expect(places.single.name, 'KLCC');
    expect(places.single.address, contains('Kuala Lumpur'));
  });

  test('Photon reverse lookup converts current coordinates to a place',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/reverse');
      return http.Response(
        jsonEncode({
          'features': [
            {
              'geometry': {
                'coordinates': [101.6869, 3.139],
              },
              'properties': {
                'countrycode': 'MY',
                'name': 'Kuala Lumpur',
                'country': 'Malaysia',
              },
            },
          ],
        }),
        200,
      );
    });

    final service = PublicTripLocationService(client: client);
    final place = await service.reverseGeocode(3.139, 101.6869);

    expect(place.name, 'Kuala Lumpur');
    expect(place.latitude, 3.139);
  });

  test('OSRM distance is converted from metres to kilometres', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'router.project-osrm.org');
      expect(request.url.path, contains('/route/v1/driving/'));
      return http.Response(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'distance': 18425.5,
              'duration': 1200,
              'geometry': {
                'coordinates': [
                  [101.6869, 3.139],
                  [101.7123, 3.1579],
                ],
              },
            },
          ],
        }),
        200,
      );
    });

    final service = PublicTripLocationService(client: client);
    final distance = await service.drivingDistanceKm(
      const TripPlace(
        name: 'From',
        address: 'From',
        latitude: 3.139,
        longitude: 101.6869,
      ),
      const TripPlace(
        name: 'To',
        address: 'To',
        latitude: 3.1579,
        longitude: 101.7123,
      ),
    );

    expect(distance, closeTo(18.4255, .0001));
  });

  test('OSRM route includes geometry for map display', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 2500,
                'duration': 300,
                'geometry': {
                  'coordinates': [
                    [101.68, 3.13],
                    [101.69, 3.14],
                  ],
                },
              }
            ],
          }),
          200,
        ));
    final route = await PublicTripLocationService(client: client).drivingRoute(
      const TripPlace(
          name: 'A', address: 'A', latitude: 3.13, longitude: 101.68),
      const TripPlace(
          name: 'B', address: 'B', latitude: 3.14, longitude: 101.69),
    );
    expect(route.distanceKm, 2.5);
    expect(route.geometry, hasLength(2));
    expect(route.durationSeconds, 300);
  });

  test('public fallback rejects coordinates outside Malaysia', () async {
    final service = PublicTripLocationService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      service.reverseGeocode(-6.2, 106.8),
      throwsA(isA<TripLocationException>()),
    );
  });
}
