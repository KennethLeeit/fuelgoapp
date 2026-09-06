import 'package:flutter/material.dart';
import '../widgets/app_bottom_nav.dart';
import '../services/station_cache_service.dart';
import 'home_screen.dart';
import 'smart_mobility_map_screen.dart';
import 'favourite_screen.dart';
import 'profile_screen.dart';

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

    StationCacheService.instance.prefetchNearby();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: AppBottomNav(
          currentIndex: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}
