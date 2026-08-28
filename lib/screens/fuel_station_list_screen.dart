import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/favourites_service.dart';
import 'station_detail_screen.dart';

class FuelStationListScreen extends StatefulWidget {
  const FuelStationListScreen({super.key});
  @override
  State<FuelStationListScreen> createState() => _FuelStationListScreenState();
}

class _FuelStationListScreenState extends State<FuelStationListScreen> {
  String _query = '';
  late Future<List<FuelStation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // Radius/limit match the Smart Mobility Map so the two screens share the
  // same cached result — reopening this screen (or the map) shortly after
  // the other one doesn't refetch from the network.
  Future<List<FuelStation>> _load({bool forceRefresh = false}) async {
    final loc = await LocationService.getCurrentLocation();
    return StationCacheService.instance.fuel(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh);
  }

  void _retry() => setState(() => _future = _load(forceRefresh: true));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('Fuel Stations', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration:
                        const InputDecoration(hintText: 'Search fuel station...', prefixIcon: Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDark,
                    side: const BorderSide(color: AppColors.cardBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Sorted by distance \u00b7 live data (OpenStreetMap)',
                  style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FutureBuilder<List<FuelStation>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _ErrorState(onRetry: _retry);
                }
                final stations = snapshot.data!
                    .where((s) => s.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();
                if (stations.isEmpty) {
                  return const Center(child: Text('No fuel stations found nearby', style: TextStyle(color: AppColors.textGrey)));
                }
                return AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) => ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: stations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final s = stations[i];
                      final isFav = FavouritesService.instance.isFuelFavourite(s.id);
                      return InkWell(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => StationDetailScreen(station: s))),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.cardBorder)),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(color: s.brandColor.withOpacity(0.12), shape: BoxShape.circle),
                                child: Icon(Icons.local_gas_station, color: s.brandColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(s.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      s.open24Hours == true
                                          ? 'Open 24 Hours'
                                          : (s.openingHoursRaw ?? 'Hours not listed'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: s.open24Hours == true ? AppColors.evGreen : AppColors.textGrey),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${s.distanceKm} km', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                  const SizedBox(height: 16),
                                  IconButton(
                                    icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                                        color: isFav ? Colors.red : AppColors.textGrey, size: 20),
                                    onPressed: () => FavouritesService.instance.toggleFuel(s.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.textGrey),
            const SizedBox(height: 12),
            const Text('Could not load nearby fuel stations.', style: TextStyle(color: AppColors.textGrey)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
