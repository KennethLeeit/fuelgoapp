import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import 'home_screen.dart';
import 'smart_mobility_map_screen.dart';
import 'favourite_screen.dart';
import 'profile_screen.dart';

/// Hosts the four bottom-nav tabs: Home, Map, Favourite, Profile.
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});
  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _index = 0;

  final _screens = const [
    HomeScreen(),
    SmartMobilityMapScreen(embedded: true),
    FavouriteScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _prefetchNearbyStations();
  }

  // Warms StationCacheService for the user's current location as soon as
  // the app reaches the main screen — same radius/limit the Fuel/EV list
  // screens and the map use, so by the time the user actually taps into
  // one of those, the data's often already there instead of showing a
  // loading spinner. Fire-and-forget: a failure here is silently retried
  // by whichever screen the user opens next.
  Future<void> _prefetchNearbyStations() async {
    try {
      final loc = await LocationService.getCurrentLocation();
      unawaited(StationCacheService.instance.fuel(loc, radiusKm: 12, limit: 40));
      unawaited(StationCacheService.instance.ev(loc, radiusKm: 12, limit: 40));
    } catch (_) {
      // Ignore — this is just a warm-up. Each screen fetches for itself
      // (with its own error handling) if this didn't pan out.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNav(currentIndex: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}
