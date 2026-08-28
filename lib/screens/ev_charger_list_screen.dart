import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/favourites_service.dart';
import 'ev_charger_detail_screen.dart';

class EVChargerListScreen extends StatefulWidget {
  const EVChargerListScreen({super.key});
  @override
  State<EVChargerListScreen> createState() => _EVChargerListScreenState();
}

class _EVChargerListScreenState extends State<EVChargerListScreen> {
  String _query = '';
  late Future<List<EVCharger>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  // Radius/limit match the Smart Mobility Map so the two screens share the
  // same cached result — reopening this screen (or the map) shortly after
  // the other one doesn't refetch from the network.
  Future<List<EVCharger>> _load({bool forceRefresh = false}) async {
    final loc = await LocationService.getCurrentLocation();
    return StationCacheService.instance.ev(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh);
  }

  void _retry() => setState(() => _future = _load(forceRefresh: true));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('EV Charger', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search EV charger...', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDark,
                    side: const BorderSide(color: AppColors.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Spacer(),
                const Text('Live data (OpenStreetMap)', style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EVCharger>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _ErrorState(onRetry: _retry);
                }
                final chargers = snapshot.data!
                    .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();
                if (chargers.isEmpty) {
                  return const Center(child: Text('No EV chargers found nearby', style: TextStyle(color: AppColors.textGrey)));
                }
                return AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) => ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: chargers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final c = chargers[i];
                      final isFav = FavouritesService.instance.isEvFavourite(c.id);
                      final color = colorForName(c.operatorName ?? c.name);
                      return InkWell(
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => EVChargerDetailScreen(charger: c))),
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
                                decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                                child: Icon(Icons.bolt, color: color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      c.maxPowerKw != null ? '${c.operatorName ?? 'Unknown operator'} \u00b7 ${c.maxPowerKw} kW' : (c.operatorName ?? 'Unknown operator'),
                                      style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                                    ),
                                    if (c.connectors.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(c.connectors.join(' \u00b7 '), style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                      c.operational == true
                                          ? 'Operational'
                                          : (c.operational == false ? 'Reported down' : 'Status unknown'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: c.operational == true
                                              ? AppColors.evGreen
                                              : (c.operational == false ? Colors.red : AppColors.textGrey)),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${c.distanceKm} km', style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                  const SizedBox(height: 16),
                                  IconButton(
                                    icon: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                                        color: isFav ? Colors.red : AppColors.textGrey, size: 20),
                                    onPressed: () => FavouritesService.instance.toggleEv(c.id),
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
  final String? message;
  const _ErrorState({required this.onRetry, this.message});
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
            Text(
              message ?? 'Could not load nearby EV chargers.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGrey),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
