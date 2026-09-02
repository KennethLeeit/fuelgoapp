import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuelgo_app/screens/cost_calculator_screen.dart';

void main() {
  testWidgets('calculator landing screen exposes both trip modes',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CostCalculatorScreen()),
    );

    expect(find.text('Trip Cost Calculator'), findsOneWidget);
    expect(find.text('Daily / Regular Route'), findsOneWidget);
    expect(find.text('Long Distance Trip'), findsOneWidget);
    expect(
        find.widgetWithText(FilledButton, 'View Saved Routes'), findsOneWidget);
  });
}
