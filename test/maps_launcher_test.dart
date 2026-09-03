import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/services/maps_launcher.dart';

void main() {
  test('directions use exact coordinates without a geocoded station name', () {
    final uri = MapsLauncher.directionsUri(
      lat: 2.7258,
      lng: 101.9424,
    );

    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['destination'], '2.7258,101.9424');
    expect(uri.query, isNot(contains('Petronas')));
  });

  test('map location search uses exact coordinates', () {
    final uri = MapsLauncher.locationUri(
      lat: 2.7258,
      lng: 101.9424,
    );

    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['query'], '2.7258,101.9424');
  });
}
