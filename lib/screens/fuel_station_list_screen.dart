import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/favourites_service.dart';
import 'station_detail_screen.dart';
import '../widgets/station_brand_image.dart';

class FuelStationListScreen extends StatefulWidget {
  const FuelStationListScreen({super.key});
  @override
  State<FuelStationListScreen> createState() => _FuelStationListScreenState();
}

class _FuelStationListScreenState extends State<FuelStationListScreen> {
  String _query = '';
  String? _brandFilter;
  String? _serviceFilter;
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
    return StationCacheService.instance
        .fuel(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh);
  }

  void _retry() {
    final nextLoad = _load(forceRefresh: true);
    setState(() {
      _future = nextLoad;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Fuel Stations',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
                    decoration: const InputDecoration(
                        hintText: 'Search fuel station...',
                        prefixIcon: Icon(Icons.search)),
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
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<FuelStation>>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <FuelStation>[];
              final brands = data.map((s) => s.brand ?? s.name).toSet().toList()
                ..sort();
              final services = data.expand((s) => s.services).toSet().toList()
                ..sort();
              final activeCount = (_brandFilter == null ? 0 : 1) +
                  (_serviceFilter == null ? 0 : 1);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFD),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded,
                            size: 18, color: AppColors.primaryBlue),
                        const SizedBox(width: 7),
                        const Text('Filter stations',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        if (activeCount > 0) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('$activeCount active',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10)),
                          ),
                        ],
                        const Spacer(),
                        if (activeCount > 0)
                          TextButton(
                            onPressed: () => setState(() {
                              _brandFilter = null;
                              _serviceFilter = null;
                            }),
                            child: const Text('Reset'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterMenu(
                            label: _brandFilter ?? 'All brands',
                            icon: Icons.local_gas_station_outlined,
                            values: brands,
                            onSelected: (value) =>
                                setState(() => _brandFilter = value),
                          ),
                          const SizedBox(width: 8),
                          _FilterMenu(
                            label: _serviceFilter ?? 'All services',
                            icon: Icons.miscellaneous_services_outlined,
                            values: services,
                            onSelected: (value) =>
                                setState(() => _serviceFilter = value),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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
                    .where((s) =>
                        s.name.toLowerCase().contains(_query.toLowerCase()) &&
                        (_brandFilter == null ||
                            (s.brand ?? s.name) == _brandFilter) &&
                        (_serviceFilter == null ||
                            s.services.contains(_serviceFilter)))
                    .toList();
                if (stations.isEmpty) {
                  return const Center(
                      child: Text('No fuel stations found nearby',
                          style: TextStyle(color: AppColors.textGrey)));
                }
                return AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) => ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: stations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final s = stations[i];
                      final isFav =
                          FavouritesService.instance.isFuelFavourite(s.id);
                      return InkWell(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    StationDetailScreen(station: s))),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.cardBorder)),
                          child: Row(
                            children: [
                              StationBrandBadge(station: s, size: 54),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(s.displayAddress,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textGrey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      s.open24Hours == true
                                          ? 'Open 24 Hours'
                                          : (s.openingHoursRaw ??
                                              'Hours not verified'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: s.open24Hours == true
                                              ? AppColors.evGreen
                                              : AppColors.textGrey),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${s.distanceKm} km',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textGrey)),
                                  const SizedBox(height: 16),
                                  IconButton(
                                    icon: Icon(
                                        isFav
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: isFav
                                            ? Colors.red
                                            : AppColors.textGrey,
                                        size: 20),
                                    onPressed: () => FavouritesService.instance
                                        .toggleFuel(s),
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

class _FilterMenu extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<String> values;
  final ValueChanged<String?> onSelected;
  const _FilterMenu(
      {required this.label,
      required this.icon,
      required this.values,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final active = !label.startsWith('All ');
    return PopupMenuButton<String>(
      onSelected: (value) => onSelected(value.isEmpty ? null : value),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '', child: Text('All')),
        ...values
            .map((value) => PopupMenuItem(value: value, child: Text(value))),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEAF1FD) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? AppColors.primaryBlue : AppColors.cardBorder),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 18,
                color: active ? AppColors.primaryBlue : AppColors.textGrey),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        active ? AppColors.primaryBlue : AppColors.textDark)),
            const SizedBox(width: 5),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: active ? AppColors.primaryBlue : AppColors.textGrey),
          ],
        ),
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
            const Icon(Icons.wifi_off_rounded,
                size: 40, color: AppColors.textGrey),
            const SizedBox(height: 12),
            const Text('Could not load nearby fuel stations.',
                style: TextStyle(color: AppColors.textGrey)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
