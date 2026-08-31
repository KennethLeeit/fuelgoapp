import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';
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
    // Usually a no-op by now — LoginScreen already started this before
    // the user even signed in — but calling it again is harmless (it just
    // refreshes the cache) and covers cases where login was skipped, e.g.
    // an already-persisted Firebase session on cold app start.
    StationCacheService.instance.prefetchNearby();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNav(currentIndex: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}
