import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../services/fuel_price_impact_service.dart';
import '../services/fuel_price_service.dart';
import '../services/saved_route_repository.dart';
import '../services/vehicle_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'trip_calculation_screen.dart';

class FuelPriceImpactScreen extends StatelessWidget {
  final FuelPriceSnapshot prices;

  const FuelPriceImpactScreen({super.key, required this.prices});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel Price Impact',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<SavedRoute>>(
        stream: SavedRouteRepository.watchMine(),
        builder: (context, routeSnapshot) {
          if (routeSnapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingState();
          }
          if (routeSnapshot.hasError) {
            return const _ImpactMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load saved routes',
              message: 'Check your connection and Firestore permissions.',
            );
          }
          return StreamBuilder<List<SavedVehicle>>(
            stream: VehicleRepository.watchSavedVehicles(),
            builder: (context, vehicleSnapshot) {
              if (vehicleSnapshot.connectionState == ConnectionState.waiting) {
                return const AppLoadingState();
              }
              final routes = routeSnapshot.data ?? const <SavedRoute>[];
              final vehicles = {
                for (final vehicle
                    in vehicleSnapshot.data ?? const <SavedVehicle>[])
                  vehicle.id: vehicle,
              };
              final usedOfficialFuels = routes
                  .map((route) =>
                      FuelPriceImpactService.officialFuelKey(route.fuelType))
                  .whereType<String>()
                  .toSet();
              final impacts = <FuelRouteImpact>[];
              for (final route in routes) {
                final vehicle = vehicles[route.vehicleId];
                if (vehicle == null) continue;
                try {
                  final impact =
                      FuelPriceImpactService.calculate(route, vehicle, prices);
                  if (impact != null) impacts.add(impact);
                } catch (_) {}
              }
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Comparing official pump prices from ${_date(prices.previousDate)} to ${prices.formattedDate}. Estimates use each saved route’s current distance, vehicle efficiency and travel days.',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Fuel Prices Used by Saved Routes',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (usedOfficialFuels.contains('ron95'))
                        _FuelPriceChangeCard(
                          label: 'RON95 (Unsubsidised)',
                          previous: prices.previousRon95,
                          current: prices.ron95,
                          color: AppColors.primaryBlue,
                        ),
                      if (usedOfficialFuels.contains('ron97'))
                        _FuelPriceChangeCard(
                          label: 'RON97',
                          previous: prices.previousRon97,
                          current: prices.ron97,
                          color: AppColors.evGreen,
                        ),
                      if (usedOfficialFuels.contains('diesel'))
                        _FuelPriceChangeCard(
                          label: 'Diesel',
                          previous: prices.previousDiesel,
                          current: prices.diesel,
                          color: AppColors.fuelOrange,
                        ),
                      if (usedOfficialFuels.isEmpty) const _NoTrackedFuelCard(),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Impact on Saved Daily Routes',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  if (impacts.isEmpty)
                    const _NoAffectedRoutesCard()
                  else
                    ...impacts.map((impact) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ImpactCard(impact: impact),
                        )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _date(DateTime? value) {
    if (value == null) return 'the previous week';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }
}

class _FuelPriceChangeCard extends StatelessWidget {
  final String label;
  final double? previous;
  final double current;
  final Color color;

  const _FuelPriceChangeCard({
    required this.label,
    required this.previous,
    required this.current,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasPrevious = previous != null && previous! > 0;
    final change = hasPrevious ? current - previous! : null;
    final changeColor = change == null || change.abs() < .005
        ? AppColors.textGrey
        : change > 0
            ? Colors.red
            : AppColors.evGreen;
    final changeText = change == null
        ? 'Previous price unavailable'
        : '${change >= 0 ? '+' : ''}RM ${change.toStringAsFixed(2)} / L';
    return Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('RM ${current.toStringAsFixed(2)} / L',
              style: TextStyle(
                  color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(
            hasPrevious
                ? 'Previous: RM ${previous!.toStringAsFixed(2)} / L'
                : 'Previous: unavailable',
            style: const TextStyle(fontSize: 10, color: AppColors.textGrey),
          ),
          const SizedBox(height: 4),
          Text(changeText,
              style: TextStyle(
                  fontSize: 11,
                  color: changeColor,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NoTrackedFuelCard extends StatelessWidget {
  const _NoTrackedFuelCard();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Row(
          children: [
            Icon(Icons.local_gas_station_outlined, color: AppColors.textGrey),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No saved route uses an official weekly fuel price.',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
            ),
          ],
        ),
      );
}

class _NoAffectedRoutesCard extends StatelessWidget {
  const _NoAffectedRoutesCard();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: const Row(
          children: [
            Icon(Icons.route_outlined, color: AppColors.textGrey),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No eligible saved daily route was found. Routes need a current saved vehicle and unsubsidised RON95, RON97 or Diesel.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textGrey, height: 1.35),
              ),
            ),
          ],
        ),
      );
}

class _ImpactCard extends StatelessWidget {
  final FuelRouteImpact impact;

  const _ImpactCard({required this.impact});

  @override
  Widget build(BuildContext context) {
    final delta = impact.weeklyDifference;
    final increased = delta > .005;
    final decreased = delta < -.005;
    final color = increased
        ? Colors.red
        : decreased
            ? AppColors.evGreen
            : AppColors.textGrey;
    final prefix = increased ? '+' : '';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripCalculationScreen(
              mode: impact.route.mode, initialRoute: impact.route),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(impact.route.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                Text('$prefix RM ${delta.toStringAsFixed(2)} / week',
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${impact.route.origin.name} → ${impact.route.destination.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Previous weekly',
                    value:
                        'RM ${impact.previousCost.weeklyCost!.toStringAsFixed(2)}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Current weekly',
                    value:
                        'RM ${impact.currentCost.weeklyCost!.toStringAsFixed(2)}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    label: 'Monthly change',
                    value:
                        '$prefix RM ${impact.monthlyDifference.toStringAsFixed(2)}',
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${impact.route.fuelType} · RM ${impact.previousUnitPrice.toStringAsFixed(2)} → RM ${impact.currentUnitPrice.toStringAsFixed(2)} / L',
              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Metric({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color ?? AppColors.textDark)),
        ],
      );
}

class _ImpactMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _ImpactMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.textGrey),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.textGrey, height: 1.4)),
            ],
          ),
        ),
      );
}
