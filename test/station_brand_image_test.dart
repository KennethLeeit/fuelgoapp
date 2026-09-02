import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/models/models.dart';
import 'package:fuelgo_app/widgets/station_brand_image.dart';

FuelStation _station(String id, String brand) => FuelStation(
      id: id,
      name: brand,
      brand: brand,
      address: 'Kuala Lumpur',
      latitude: 3.139,
      longitude: 101.687,
      brandColor: Colors.blue,
    );

void main() {
  testWidgets('station badge updates its logo when a filtered row is reused',
      (tester) async {
    Future<void> pumpStation(FuelStation station) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StationBrandBadge(
            key: const ValueKey('reused-list-position'),
            station: station,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpStation(_station('shell', 'Shell'));
    var image = tester.widget<Image>(find.byType(Image));
    expect(
        (image.image as AssetImage).assetName, 'assets/images/logo_shell.png');

    await pumpStation(_station('petronas', 'Petronas'));
    image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName,
        'assets/images/logo_petronas.png');
  });
}
