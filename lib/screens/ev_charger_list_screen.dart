import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/favourites_service.dart';
import '../services/ev_operator_utils.dart';
import '../widgets/ev_charger_brand_image.dart';
import '../widgets/ui_kit.dart';
import 'ev_charger_detail_screen.dart';

enum _SortBy { distance, powerHighToLow, nameAZ, statusFirst }

extension on _SortBy {
  String get label {
    switch (this) {
      case _SortBy.distance:
        return 'Nearest first';
      case _SortBy.powerHighToLow:
        return 'Fastest charging';
      case _SortBy.nameAZ:
        return 'Name A\u2013Z';
      case _SortBy.statusFirst:
        return 'Operational first';
    }
  }
}

class EVChargerListScreen extends StatefulWidget {
  const EVChargerListScreen({super.key});
  @override
  State<EVChargerListScreen> createState() => _EVChargerListScreenState();
}

class _EVChargerListScreenState extends State<EVChargerListScreen> {
  String _query = '';
  String? _operatorFilter;
  String? _connectorFilter;
  _SortBy _sortBy = _SortBy.distance;
  late Future<List<EVCharger>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<EVCharger>> _load({bool forceRefresh = false}) async {
    final loc = await LocationService.getSharedCurrentLocation();
    return StationCacheService.instance
        .ev(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh);
  }

  void _retry() => setState(() => _future = _load(forceRefresh: true));

  String _operatorLabel(EVCharger c) =>
      normaliseEvOperator(c.operatorName) ?? c.operatorName ?? c.name;

  List<EVCharger> _sorted(List<EVCharger> chargers) {
    final sorted = [...chargers];
    switch (_sortBy) {
      case _SortBy.distance:
        sorted.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
        break;
      case _SortBy.powerHighToLow:
        sorted.sort((a, b) {
          final ap = a.maxPowerKw;
          final bp = b.maxPowerKw;
          if (ap == null && bp == null)
            return a.distanceKm.compareTo(b.distanceKm);
          if (ap == null) return 1;
          if (bp == null) return -1;
          return bp.compareTo(ap);
        });
        break;
      case _SortBy.nameAZ:
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortBy.statusFirst:
        int rank(EVCharger c) =>
            c.operational == true ? 0 : (c.operational == null ? 1 : 2);
        sorted.sort((a, b) {
          final r = rank(a).compareTo(rank(b));
          return r != 0 ? r : a.distanceKm.compareTo(b.distanceKm);
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
        title: const Text('EV Charger',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                  hintText: 'Search EV charger...',
                  prefixIcon: Icon(Icons.search)),
            ),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<EVCharger>>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <EVCharger>[];
              final operators = data.map(_operatorLabel).toSet().toList()
                ..sort();
              final connectors =
                  data.expand((c) => c.connectors).toSet().toList()..sort();
              final activeCount = (_operatorFilter == null ? 0 : 1) +
                  (_connectorFilter == null ? 0 : 1);
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
                              _operatorFilter = null;
                              _connectorFilter = null;
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
                            label: _operatorFilter ?? 'All networks',
                            icon: Icons.ev_station_outlined,
                            values: operators,
                            onSelected: (value) =>
                                setState(() => _operatorFilter = value),
                          ),
                          const SizedBox(width: 8),
                          _FilterMenu(
                            label: _connectorFilter ?? 'All connectors',
                            icon: Icons.power_rounded,
                            values: connectors,
                            onSelected: (value) =>
                                setState(() => _connectorFilter = value),
                          ),
                          const SizedBox(width: 8),
                          Container(
                              width: 1,
                              height: 24,
                              color: AppColors.cardBorder),
                          const SizedBox(width: 8),
                          _SortMenu(
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
                const Text('Live data (Open Charge Map)',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EVCharger>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const AppLoadingState(
                      message: 'Finding EV chargers nearby\u2026');
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return AppErrorState(
                      message: 'Could not load nearby EV chargers.',
                      onRetry: _retry);
                }
                final filtered = snapshot.data!
                    .where((c) =>
                        c.name.toLowerCase().contains(_query.toLowerCase()) &&
                        (_operatorFilter == null ||
                            _operatorLabel(c) == _operatorFilter) &&
                        (_connectorFilter == null ||
                            c.connectors.contains(_connectorFilter)))
                    .toList();
                final chargers = _sorted(filtered);
                if (chargers.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.ev_station_outlined,
                    title: 'No EV chargers found nearby',
                    message: 'Try widening your search or adjusting filters.',
                  );
                }
                return AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) => ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: chargers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final c = chargers[i];
                      final isFav =
                          FavouritesService.instance.isEvFavourite(c.id);
                      final tier = chargeSpeedTierFor(c.maxPowerKw);
                      return InkWell(
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    EVChargerDetailScreen(charger: c))),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: Theme.of(context).dividerColor)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              EVChargerBrandBadge(charger: c, size: 46),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(_operatorLabel(c),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textGrey)),
                                    if (c.connectors.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: c.connectors.map((conn) {
                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .dividerColor
                                                  .withValues(alpha: .3),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(iconForConnector(conn),
                                                    size: 11,
                                                    color: Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge
                                                            ?.color ??
                                                        AppColors.textDark),
                                                const SizedBox(width: 3),
                                                Text(conn,
                                                    style: TextStyle(
                                                        fontSize: 10,
                                                        color: Theme.of(context)
                                                                .textTheme
                                                                .bodyLarge
                                                                ?.color ??
                                                            AppColors
                                                                .textDark)),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (c.maxPowerKw != null) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: colorForSpeedTier(tier)
                                                  .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                                '${c.maxPowerKw} kW \u00b7 ${labelForSpeedTier(tier)}',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: colorForSpeedTier(
                                                        tier))),
                                          ),
                                          const SizedBox(width: 6),
                                        ],
                                        Icon(
                                          c.operational == true
                                              ? Icons.check_circle
                                              : (c.operational == false
                                                  ? Icons.error
                                                  : Icons.help_outline),
                                          size: 12,
                                          color: c.operational == true
                                              ? AppColors.evGreen
                                              : (c.operational == false
                                                  ? Colors.red
                                                  : AppColors.textGrey),
                                        ),
                                        const SizedBox(width: 3),
                                        Flexible(
                                          child: Text(
                                            c.operational == true
                                                ? 'Operational'
                                                : (c.operational == false
                                                    ? 'Reported down'
                                                    : 'Status unknown'),
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: c.operational == true
                                                    ? AppColors.evGreen
                                                    : (c.operational == false
                                                        ? Colors.red
                                                        : AppColors.textGrey)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${c.distanceKm} km',
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
                                    onPressed: () =>
                                        FavouritesService.instance.toggleEv(c),
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

class _SortMenu extends StatelessWidget {
  final _SortBy current;
  final ValueChanged<_SortBy> onSelected;
  const _SortMenu({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SortBy>(
      onSelected: onSelected,
      itemBuilder: (_) => _SortBy.values
          .map((option) => PopupMenuItem(
                value: option,
                child: Row(
                  children: [
                    if (option == current)
                      const Icon(Icons.check,
                          size: 16, color: AppColors.primaryBlue)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(option.label),
                  ],
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort_rounded, size: 18, color: AppColors.textGrey),
            const SizedBox(width: 7),
            Text(current.label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color ??
                        AppColors.textDark)),
            const SizedBox(width: 5),
            const Icon(Icons.keyboard_arrow_down_rounded,
                size: 17, color: AppColors.textGrey),
          ],
        ),
      ),
    );
  }
}
