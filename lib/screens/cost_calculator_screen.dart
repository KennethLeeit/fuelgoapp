import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../theme/app_theme.dart';
import 'saved_routes_screen.dart';
import 'trip_calculation_screen.dart';

class CostCalculatorScreen extends StatelessWidget {
  const CostCalculatorScreen({super.key});

  Future<void> _openMode(BuildContext context, TripMode mode,
      {SavedRoute? route}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripCalculationScreen(mode: mode, initialRoute: route),
      ),
    );
  }

  Future<void> _openSavedRoutes(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SavedRoutesScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trip Cost Calculator',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.primaryBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: .24),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: Color(0x26FFFFFF),
                    child: Icon(Icons.calculate_outlined,
                        color: Colors.white, size: 28),
                  ),
                  SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose how you travel',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Use your saved vehicle, current prices and actual driving distance.',
                          style: TextStyle(
                            color: Color(0xFFDDE8FF),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _ModeCard(
              icon: Icons.calendar_month_outlined,
              color: AppColors.primaryBlue,
              title: 'Daily / Regular Route',
              subtitle: 'Estimate daily, weekly and monthly travel costs.',
              onTap: () => _openMode(context, TripMode.daily),
            ),
            const SizedBox(height: 14),
            _ModeCard(
              icon: Icons.route_outlined,
              color: AppColors.fuelOrange,
              title: 'Long Distance Trip',
              subtitle: 'Estimate one-way or round-trip energy cost.',
              onTap: () => _openMode(context, TripMode.longDistance),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => _openSavedRoutes(context),
              icon: const Icon(Icons.bookmarks_outlined),
              label: const Text('View Saved Routes'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 3,
                shadowColor: AppColors.navy.withValues(alpha: .3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: .08),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundColor: color.withValues(alpha: .1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textGrey,
                          height: 1.35)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textGrey),
          ],
        ),
      ),
    );
  }
}
