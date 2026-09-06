import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/favourites_service.dart';
import 'station_detail_screen.dart';
import '../widgets/station_brand_image.dart';
import '../widgets/ui_kit.dart';

enum _FuelSortBy { distance, nameAZ, open24First }

extension on _FuelSortBy {
  String get label {
    switch (this) {
      case _FuelSortBy.distance:
        return 'Nearest first';
      case _FuelSortBy.nameAZ:
        return 'Name A–Z';
      case _FuelSortBy.open24First:
        return 'Open 24 hours first';
    }
  }
}

class FuelStationListScreen extends StatefulWidget {
  const FuelStationListScreen({super.key});
  @override
  State<FuelStationListScreen> createState() => _FuelStationListScreenState();
}

class _FuelStationListScreenState extends State<FuelStationListScreen> {
  String _query = '';
  String? _brandFilter;
  String? _serviceFilter;
  _FuelSortBy _sortBy = _FuelSortBy.distance;
  late Future<List<FuelStation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<FuelStation>> _load({bool forceRefresh = false}) async {
    final loc = await LocationService.getSharedCurrentLocation();
    return StationCacheService.instance
        .fuel(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh);
  }

  void _retry() {
    final nextLoad = _load(forceRefresh: true);
    setState(() {
      _future = nextLoad;
    });
  }

  String _brandLabel(FuelStation station) {
    final raw = (station.brand?.trim().isNotEmpty ?? false)
        ? station.brand!.trim()
        : station.name.trim();
    final value = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (value.contains('petronas')) return 'Petronas';
    if (value.contains('bhpetrol') || value.contains('boustead')) {
      return 'BHPetrol';
    }
    if (value.contains('petron')) return 'Petron';
    if (value.contains('shell')) return 'Shell';
    if (value.contains('caltex')) return 'Caltex';
    return raw.isEmpty ? 'Other' : raw;
  }

  bool _matchesSearch(FuelStation station) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return station.name.toLowerCase().contains(query) ||
        _brandLabel(station).toLowerCase().contains(query) ||
        station.displayAddress.toLowerCase().contains(query);
  }

  bool _matchesService(FuelStation station) {
    final filter = _serviceFilter?.trim().toLowerCase();
    if (filter == null) return true;
    return station.services
        .any((service) => service.trim().toLowerCase() == filter);
  }

  List<FuelStation> _sorted(List<FuelStation> stations) {
    final sorted = [...stations];
    switch (_sortBy) {
      case _FuelSortBy.distance:
        sorted.sort((a, b) {
          final distance = a.distanceKm.compareTo(b.distanceKm);
          return distance != 0
              ? distance
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case _FuelSortBy.nameAZ:
        sorted.sort((a, b) {
          final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return name != 0 ? name : a.distanceKm.compareTo(b.distanceKm);
        });
        break;
      case _FuelSortBy.open24First:
        int rank(FuelStation station) => station.open24Hours == true
            ? 0
            : (station.open24Hours == null ? 1 : 2);
        sorted.sort((a, b) {
          final availability = rank(a).compareTo(rank(b));
          return availability != 0
              ? availability
              : a.distanceKm.compareTo(b.distanceKm);
        });
        break;
    }
    return sorted;
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
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                  hintText: 'Search fuel station...',
                  prefixIcon: Icon(Icons.search)),
            ),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<FuelStation>>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <FuelStation>[];
              final brands = data.map(_brandLabel).toSet().toList()..sort();
              final services = data
                  .expand((s) => s.services)
                  .map((service) => service.trim())
                  .where((service) => service.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
              final activeCount = (_brandFilter == null ? 0 : 1) +
                  (_serviceFilter == null ? 0 : 1);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
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
                        const Text('Filter & sort',
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
                          const SizedBox(width: 8),
                          Container(
                              width: 1,
                              height: 24,
                              color: AppColors.cardBorder),
                          const SizedBox(width: 8),
                          _FuelSortMenu(
                            current: _sortBy,
                            onSelected: (value) =>
                                setState(() => _sortBy = value),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).textTheme.bodyLarge?.color ??
                            AppColors.textDark,
                    side: BorderSide(color: Theme.of(context).dividerColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Spacer(),
                const Text('Live data (OpenStreetMap)',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FutureBuilder<List<FuelStation>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingState(
                      message: 'Finding fuel stations nearby\u2026');
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return AppErrorState(
                      message: 'Could not load nearby fuel stations.',
                      onRetry: _retry);
                }
                final filtered = snapshot.data!
                    .where((station) =>
                        _matchesSearch(station) &&
                        (_brandFilter == null ||
                            _brandLabel(station) == _brandFilter) &&
                        _matchesService(station))
                    .toList();
                final stations = _sorted(filtered);
                if (stations.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.local_gas_station_outlined,
                    title: 'No fuel stations found nearby',
                    message: 'Try widening your search or adjusting filters.',
                  );
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
                        key: ValueKey(s.id),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    StationDetailScreen(station: s))),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Theme.of(context).dividerColor)),
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
          color: active
              ? AppColors.primaryBlue.withValues(alpha: .12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? AppColors.primaryBlue
                  : Theme.of(context).dividerColor),
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
                    color: active
                        ? AppColors.primaryBlue
                        : (Theme.of(context).textTheme.bodyLarge?.color ??
                            AppColors.textDark))),
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

class _FuelSortMenu extends StatelessWidget {
  final _FuelSortBy current;
  final ValueChanged<_FuelSortBy> onSelected;

  const _FuelSortMenu({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_FuelSortBy>(
      onSelected: onSelected,
      itemBuilder: (_) => _FuelSortBy.values
          .map((value) => PopupMenuItem(
                value: value,
                child: Row(
                  children: [
                    if (value == current)
                      const Icon(Icons.check_rounded,
                          size: 17, color: AppColors.primaryBlue)
                    else
                      const SizedBox(width: 17),
                    const SizedBox(width: 8),
                    Text(value.label),
                  ],
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryBlue),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert_rounded,
                size: 18, color: AppColors.primaryBlue),
            const SizedBox(width: 7),
            Text(current.label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryBlue)),
            const SizedBox(width: 5),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 17, color: AppColors.primaryBlue),
          ],
        ),
      ),
    );
  }
}
