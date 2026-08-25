import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/osm_fuel_service.dart';
import '../services/osm_ev_charger_service.dart';
import '../services/favourites_service.dart';
import 'station_detail_screen.dart';
import 'ev_charger_detail_screen.dart';

/// Shows favourited stations/chargers. Since station/charger data now comes
/// from live APIs (not a fixed mock list), this re-fetches nearby places
/// and filters to whichever ones are in FavouritesService — so a favourite
/// will only show up here while it's within your current search radius.
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

  Future<_FavData> _load() async {
    final loc = await LocationService.getCurrentLocation();
    final results = await Future.wait([
      OsmFuelService.fetchNearby(loc, radiusKm: 20, limit: 60),
      OsmEvChargerService.fetchNearby(loc, radiusKm: 20, limit: 60),
    ]);
    return _FavData(results[0] as List<FuelStation>, results[1] as List<EVCharger>);
  }

  void _refresh() => setState(() => _future = _load());

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
                  const Text('Favourite', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.refresh, color: AppColors.textGrey), onPressed: _refresh),
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
                              const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.textGrey),
                              const SizedBox(height: 12),
                              const Text('Could not load your favourites.', style: TextStyle(color: AppColors.textGrey)),
                              const SizedBox(height: 12),
                              ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                            ],
                          ),
                        );
                      }

                      // Favourites are always shown here regardless of the
                      // vehicle preference filter used elsewhere — a saved
                      // favourite shouldn't disappear just because the
                      // display preference changed.
                      final favStations =
                          snapshot.data!.stations.where((s) => FavouritesService.instance.isFuelFavourite(s.id)).toList();
                      final favChargers =
                          snapshot.data!.chargers.where((c) => FavouritesService.instance.isEvFavourite(c.id)).toList();
                      final isEmpty = favStations.isEmpty && favChargers.isEmpty;

                      if (isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.favorite_border, size: 60, color: AppColors.textGrey),
                              SizedBox(height: 12),
                              Text('No favourites yet', style: TextStyle(color: AppColors.textGrey)),
                              SizedBox(height: 4),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 24),
                                child: Text(
                                  'Tap the heart icon on stations or chargers to save them here. Favourites show up while they\'re within your current search area.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView(
                        children: [
                          ...favStations.map((s) => _favTile(
                                icon: Icons.local_gas_station,
                                color: s.brandColor,
                                title: s.name,
                                subtitle: '${s.distanceKm} km',
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StationDetailScreen(station: s))),
                                onRemove: () => FavouritesService.instance.toggleFuel(s.id),
                              )),
                          ...favChargers.map((c) => _favTile(
                                icon: Icons.bolt,
                                color: colorForName(c.operatorName ?? c.name),
                                title: c.name,
                                subtitle: '${c.distanceKm} km',
                                onTap: () =>
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => EVChargerDetailScreen(charger: c))),
                                onRemove: () => FavouritesService.instance.toggleEv(c.id),
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
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
      required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: IconButton(icon: const Icon(Icons.favorite, color: Colors.red), onPressed: onRemove),
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
