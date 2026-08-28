import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/favourites_service.dart';
import '../widgets/station_brand_image.dart';
import 'station_detail_screen.dart';
import 'ev_charger_detail_screen.dart';

/// Fuel favourites are stored locally, so they remain visible without a
/// second network request and outside the current search radius.
class FavouriteScreen extends StatefulWidget {
  const FavouriteScreen({super.key});
  @override
  State<FavouriteScreen> createState() => _FavouriteScreenState();
}

class _FavouriteScreenState extends State<FavouriteScreen> {
  late Future<_FavData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FavData> _load({bool forceRefresh = false}) async {
    final loc = await LocationService.getCurrentLocation();
    List<EVCharger> chargers = const [];
    try {
      chargers = await StationCacheService.instance
          .ev(loc, radiusKm: 20, limit: 60, forceRefresh: forceRefresh);
    } catch (_) {}
    return _FavData(FavouritesService.instance.fuelStations, chargers);
  }

  void _refresh() {
    final nextLoad = _load(forceRefresh: true);
    setState(() {
      _future = nextLoad;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Favourite',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(
                      icon:
                          const Icon(Icons.refresh, color: AppColors.textGrey),
                      onPressed: _refresh),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) => FutureBuilder<_FavData>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_rounded,
                                  size: 40, color: AppColors.textGrey),
                              const SizedBox(height: 12),
                              const Text('Could not load your favourites.',
                                  style: TextStyle(color: AppColors.textGrey)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                  onPressed: _refresh,
                                  child: const Text('Retry')),
                            ],
                          ),
                        );
                      }

                      // Favourites are always shown here regardless of the
                      // vehicle preference filter used elsewhere — a saved
                      // favourite shouldn't disappear just because the
                      // display preference changed.
                      final favStations =
                          FavouritesService.instance.fuelStations;
                      final favChargers = snapshot.data!.chargers
                          .where((c) =>
                              FavouritesService.instance.isEvFavourite(c.id))
                          .toList();
                      final isEmpty =
                          favStations.isEmpty && favChargers.isEmpty;

                      if (isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.favorite_border,
                                  size: 60, color: AppColors.textGrey),
                              SizedBox(height: 12),
                              Text('No favourites yet',
                                  style: TextStyle(color: AppColors.textGrey)),
                              SizedBox(height: 4),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Tap the heart icon on a station or charger to save it here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.textGrey, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView(
                        children: [
                          ...favStations.map((s) => _favTile(
                                leading: StationBrandBadge(
                                  station: s,
                                  size: 48,
                                ),
                                title: s.name,
                                subtitle: '${s.distanceKm} km',
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            StationDetailScreen(station: s))),
                                onRemove: () =>
                                    FavouritesService.instance.toggleFuel(s),
                              )),
                          ...favChargers.map((c) => _favTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      colorForName(c.operatorName ?? c.name)
                                          .withValues(alpha: 0.12),
                                  child: Icon(
                                    Icons.bolt,
                                    color:
                                        colorForName(c.operatorName ?? c.name),
                                  ),
                                ),
                                title: c.name,
                                subtitle: '${c.distanceKm} km',
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            EVChargerDetailScreen(charger: c))),
                                onRemove: () =>
                                    FavouritesService.instance.toggleEv(c.id),
                              )),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _favTile(
      {required Widget leading,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          leading: leading,
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: IconButton(
              icon: const Icon(Icons.favorite, color: Colors.red),
              onPressed: onRemove),
        ),
      ),
    );
  }
}

class _FavData {
  final List<FuelStation> stations;
  final List<EVCharger> chargers;
  _FavData(this.stations, this.chargers);
}
