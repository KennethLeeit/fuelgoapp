import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/fuel_price_service.dart';
import '../services/reference_prices.dart';
import '../services/vehicle_preference_service.dart';
import '../services/notice_service.dart';
import '../services/vehicle_repository.dart';
import 'fuel_station_list_screen.dart';
import 'ev_charger_list_screen.dart';
import 'cost_calculator_screen.dart';
import 'notifications_screen.dart';
import 'add_vehicle_dialog.dart';

/// Reads [key] from [data] and coerces it to a double, whether it was
/// stored as a Firestore number or as a string.
double _doubleFromDynamic(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// Picks the fuel-pump icon colour based on the vehicle's fuel type:
/// standard petrol keeps the existing orange, premium petrol is green,
/// diesel is black. Electric vehicles are handled separately by the caller.
Color _fuelIconColor(String fuelType) {
  final f = fuelType.toLowerCase();
  if (f.contains('diesel')) return Colors.black;
  if (f.contains('premium')) return Colors.green;
  return AppColors.fuelOrange;
}

/// A lightweight read of a saved vehicle for the "My Vehicles" home strip.
class _HomeVehicle {
  final String make;
  final String model;
  final String fuelType;
  final double combinedKmL;
  final bool isElectric;
  final bool isFavourite;

  _HomeVehicle.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc)
      : make = doc.data()['make'] as String? ?? '',
        model = doc.data()['model'] as String? ?? '',
        fuelType = doc.data()['fuelType'] as String? ?? '',
        combinedKmL = _doubleFromDynamic(doc.data(), 'combinedKmL'),
        isElectric = doc.data()['isElectric'] as bool? ?? false,
        isFavourite = doc.data()['isFavourite'] as bool? ?? false;
}

/// Estimated cost to drive 100km in [vehicle], in RM.
///
/// For fuel vehicles this uses the live/reference price for its fuel type
/// (RON95 standard petrol uses the fixed subsidised rate; RON97/"premium"
/// and diesel use the current weekly price). For electric vehicles it uses
/// the median ("mid") rate across the EV charging providers we track.
/// Returns null if the figure isn't available yet (e.g. weekly prices
/// still loading, or the vehicle has no recorded km/L).
double? _costPer100Km(_HomeVehicle vehicle, FuelPriceSnapshot? prices) {
  if (vehicle.combinedKmL <= 0) return null;
  double unitPrice;
  if (vehicle.isElectric) {
    final rates = ReferencePrices.evProviderRates.values.toList()..sort();
    if (rates.isEmpty) return null;
    final mid = rates.length.isOdd
        ? rates[rates.length ~/ 2]
        : (rates[rates.length ~/ 2 - 1] + rates[rates.length ~/ 2]) / 2;
    unitPrice = mid;
  } else {
    final f = vehicle.fuelType.toLowerCase();
    if (f.contains('diesel')) {
      if (prices == null) return null;
      unitPrice = prices.diesel;
    } else if (f.contains('premium') || f.contains('ron97')) {
      if (prices == null) return null;
      unitPrice = prices.ron97;
    } else {
      // Standard RON95 uses the fixed subsidised pump rate most everyday
      // cars actually pay, so this doesn't need to wait on the live fetch.
      unitPrice = ReferencePrices.ron95Subsidised;
    }
  }
  return (100 / vehicle.combinedKmL) * unitPrice;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<FuelPriceSnapshot> _priceFuture;
  bool _hasUnseenNotices = false;

  @override
  void initState() {
    super.initState();
    _priceFuture = FuelPriceService.fetchLatest();
    _refreshUnseenBadge();
  }

  void _refresh() {
    setState(() {
      _priceFuture = FuelPriceService.fetchLatest();
    });
    _refreshUnseenBadge();
  }

  // Re-checks whether there's an unseen notice and updates the bell badge.
  // Called on load, after a price refresh, and after returning from the
  // Notifications screen (which marks the latest snapshot as seen) — that
  // last one is what makes the red dot actually clear once the user has
  // looked at it, instead of staying on until something else happens to
  // rebuild this screen.
  Future<void> _refreshUnseenBadge() async {
    try {
      final data = await _priceFuture;
      final unseen = await NoticeService.hasUnseen(data);
      if (mounted) setState(() => _hasUnseenNotices = unseen);
    } catch (_) {
      // Leave the badge as-is if the price fetch failed.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    _refreshUnseenBadge();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await _priceFuture.catchError((_) {
              return FuelPriceSnapshot(
                date: DateTime.now(),
                ron95: 0,
                ron97: 0,
                diesel: 0,
                ron95Change: 0,
                ron97Change: 0,
                dieselChange: 0,
              );
            });
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Text('Fuel',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textDark)),
                        Text('Go',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.evGreen)),
                      ],
                    ),
                    GestureDetector(
                      onTap: _openNotifications,
                      child: Stack(
                        children: [
                          const Icon(Icons.notifications_none_rounded, size: 26),
                          if (_hasUnseenNotices)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Quick Access', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: VehiclePreferenceService.instance,
                  builder: (context, _) {
                    final vp = VehiclePreferenceService.instance;
                    final cards = <Widget>[
                      if (vp.showFuel)
                        _QuickAccessCard(
                          icon: Icons.local_gas_station,
                          color: AppColors.fuelOrange,
                          title: 'Fuel Station',
                          subtitle: 'Find nearby fuel stations',
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => const FuelStationListScreen())),
                        ),
                      if (vp.showEV)
                        _QuickAccessCard(
                          icon: Icons.ev_station,
                          color: AppColors.evGreen,
                          title: 'EV Charger',
                          subtitle: 'Find nearby EV chargers',
                          onTap: () => Navigator.push(
                              context, MaterialPageRoute(builder: (_) => const EVChargerListScreen())),
                        ),
                      _QuickAccessCard(
                        icon: Icons.calculate_outlined,
                        color: AppColors.primaryBlue,
                        title: 'Cost Calculator',
                        subtitle: vp.isLocked
                            ? (vp.showFuel ? 'Estimate fuel cost' : 'Estimate charging cost')
                            : 'Estimate fuel or charging cost',
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const CostCalculatorScreen())),
                      ),
                    ];
                    return Row(children: _spaced(cards));
                  },
                ),
                const SizedBox(height: 24),
                const Text('My Vehicles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 112,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: VehicleRepository.watchMyVehicles(),
                    builder: (context, vehicleSnapshot) {
                      if (vehicleSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final docs = vehicleSnapshot.data?.docs ?? [];
                      final vehicles = docs.map(_HomeVehicle.fromDoc).toList();
                      // Favourite first, otherwise keep the newest-first order
                      // the stream already gives us.
                      final favourites = vehicles.where((v) => v.isFavourite);
                      final others = vehicles.where((v) => !v.isFavourite);
                      final shown = [...favourites, ...others];
                      return FutureBuilder<FuelPriceSnapshot>(
                        future: _priceFuture,
                        builder: (context, priceSnapshot) {
                          final prices = priceSnapshot.data;
                          return ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final vehicle in shown) ...[
                                _HomeVehicleCard(
                                  vehicle: vehicle,
                                  costPer100Km: _costPer100Km(vehicle, prices),
                                ),
                                const SizedBox(width: 10),
                              ],
                              _AddVehicleCard(
                                onTap: () => showAddVehicleDialog(context),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: VehiclePreferenceService.instance,
                  builder: (context, _) {
                    if (!VehiclePreferenceService.instance.showFuel) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Weekly Fuel Prices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20, color: AppColors.textGrey),
                              onPressed: _refresh,
                              tooltip: 'Refresh prices',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<FuelPriceSnapshot>(
                          future: _priceFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const _PriceRowSkeleton();
                            }
                            if (snapshot.hasError || !snapshot.hasData) {
                              return _PriceRowError(onRetry: _refresh);
                            }
                            final data = snapshot.data!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _PriceCard(
                                        label: 'RON95 (Subsidised)',
                                        price: 'RM ${ReferencePrices.ron95Subsidised.toStringAsFixed(2)} /L',
                                        note: 'Fixed rate',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _PriceCard(
                                        label: 'RON95 (Unsubsidised)',
                                        price: 'RM ${data.ron95.toStringAsFixed(2)} /L',
                                        change: data.ron95Change,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _PriceCard(
                                        label: 'RON97',
                                        price: 'RM ${data.ron97.toStringAsFixed(2)} /L',
                                        change: data.ron97Change,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _PriceCard(
                                        label: 'Diesel',
                                        price: 'RM ${data.diesel.toStringAsFixed(2)} /L',
                                        change: data.dieselChange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'As of ${data.formattedDate} \u00b7 Source: data.gov.my',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textGrey),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
                AnimatedBuilder(
                  animation: VehiclePreferenceService.instance,
                  builder: (context, _) {
                    if (!VehiclePreferenceService.instance.showEV) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('EV Charging Prices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        const Text(
                          'Indicative rates — varies by location & power. Check the operator\'s app for live pricing.',
                          style: TextStyle(fontSize: 10, color: AppColors.textGrey),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: () {
                            final entries = ReferencePrices.evProviderRates.entries.toList();
                            final cards = <Widget>[];
                            for (var i = 0; i < entries.length; i++) {
                              cards.add(Expanded(
                                child: _EVPriceCard(
                                  label: entries[i].key,
                                  price: 'from RM ${entries[i].value.toStringAsFixed(2)} /kWh',
                                ),
                              ));
                              if (i != entries.length - 1) cards.add(const SizedBox(width: 10));
                            }
                            return cards;
                          }(),
                        ),
                        const SizedBox(height: 20),
                      ],
                    );
                  },
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFEAF1FD), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined, color: AppColors.primaryBlue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Stay Updated!', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('Get the latest updates on fuel prices, promotions and station availability.',
                                style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.primaryBlue),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _spaced(List<Widget> cards) {
    final list = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      list.add(Expanded(child: cards[i]));
      if (i != cards.length - 1) list.add(const SizedBox(width: 10));
    }
    return list;
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickAccessCard(
      {required this.icon,
        required this.color,
        required this.title,
        required this.subtitle,
        required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder)),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: AppColors.textGrey)),
          ],
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final String label;
  final String price;
  // Week-over-week change, in RM. Null for prices that don't track a
  // weekly change (e.g. the fixed subsidised rate) — shows `note` instead.
  final double? change;
  final String? note;
  const _PriceCard({required this.label, required this.price, this.change, this.note});

  @override
  Widget build(BuildContext context) {
    final hasChange = change != null;
    final up = hasChange && change! > 0;
    final flat = hasChange && change == 0;
    final color = flat ? AppColors.textGrey : (up ? Colors.red : AppColors.evGreen);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.fuelOrange, fontSize: 13)),
          const SizedBox(height: 6),
          Text(price, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          if (hasChange)
            Row(
              children: [
                if (!flat) Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: color),
                Text('${change!.abs().toStringAsFixed(2)}', style: TextStyle(fontSize: 11, color: color)),
              ],
            )
          else if (note != null)
            Text(note!, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
        ],
      ),
    );
  }
}

class _PriceRowSkeleton extends StatelessWidget {
  const _PriceRowSkeleton();
  @override
  Widget build(BuildContext context) {
    Widget box() => Expanded(
      child: Container(
        height: 78,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder)),
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textGrey),
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(children: [box(), const SizedBox(width: 10), box()]),
        const SizedBox(height: 10),
        Row(children: [box(), const SizedBox(width: 10), box()]),
      ],
    );
  }
}

class _PriceRowError extends StatelessWidget {
  final VoidCallback onRetry;
  const _PriceRowError({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.textGrey, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Could not load live fuel prices.', style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EVPriceCard extends StatelessWidget {
  final String label;
  final String price;
  const _EVPriceCard({required this.label, required this.price});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, size: 14, color: AppColors.evGreen),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(price, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

class _HomeVehicleCard extends StatelessWidget {
  final _HomeVehicle vehicle;
  final double? costPer100Km;
  const _HomeVehicleCard({required this.vehicle, required this.costPer100Km});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                vehicle.isElectric ? Icons.electric_car : Icons.local_gas_station,
                size: 20,
                color: vehicle.isElectric ? AppColors.evGreen : _fuelIconColor(vehicle.fuelType),
              ),
              const Spacer(),
              if (vehicle.isFavourite) const Icon(Icons.star, size: 14, color: Colors.amber),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${vehicle.make} ${vehicle.model}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const Spacer(),
          Text(
            costPer100Km == null ? '—' : 'RM ${costPer100Km!.toStringAsFixed(2)} /100km',
            style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }
}

class _AddVehicleCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddVehicleCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, color: AppColors.primaryBlue, size: 24),
              SizedBox(height: 6),
              Text('Add Vehicle',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryBlue)),
            ],
          ),
        ),
      ),
    );
  }
}