import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/maps_launcher.dart';
import '../services/favourites_service.dart';

class EVChargerDetailScreen extends StatefulWidget {
  final EVCharger charger;
  const EVChargerDetailScreen({super.key, required this.charger});
  @override
  State<EVChargerDetailScreen> createState() => _EVChargerDetailScreenState();
}

class _EVChargerDetailScreenState extends State<EVChargerDetailScreen> {
  String? _selectedConnector;

  @override
  void initState() {
    super.initState();
    if (widget.charger.connectors.isNotEmpty) {
      _selectedConnector = widget.charger.connectors.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.charger;
    final color = colorForName(c.operatorName ?? c.name);
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withOpacity(0.85), color.withOpacity(0.4)])),
                  child: Center(child: Icon(Icons.ev_station, color: Colors.white.withOpacity(0.9), size: 70)),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _circleIconButton(Icons.arrow_back_ios_new, () => Navigator.pop(context)),
                        AnimatedBuilder(
                          animation: FavouritesService.instance,
                          builder: (context, _) {
                            final isFav = FavouritesService.instance.isEvFavourite(c.id);
                            return _circleIconButton(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              () => FavouritesService.instance.toggleEv(c),
                              color: isFav ? Colors.red : AppColors.textDark,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (c.operatorName != null) ...[
                    const SizedBox(height: 2),
                    Text(c.operatorName!, style: const TextStyle(color: AppColors.textGrey)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textGrey),
                      const SizedBox(width: 4),
                      Text('${c.distanceKm} km away', style: const TextStyle(color: AppColors.textGrey)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.operational == true ? 'Operational' : (c.operational == false ? 'Reported down' : 'Status unknown'),
                    style: TextStyle(
                        color: c.operational == true
                            ? AppColors.evGreen
                            : (c.operational == false ? Colors.red : AppColors.textGrey),
                        fontWeight: FontWeight.w600),
                  ),
                  if (c.connectors.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Connector Type', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: c.connectors.map((conn) {
                        final selected = conn == _selectedConnector;
                        return ChoiceChip(
                          label: Text(conn),
                          selected: selected,
                          onSelected: (_) => setState(() => _selectedConnector = conn),
                          selectedColor: AppColors.evGreen.withOpacity(0.15),
                          labelStyle:
                              TextStyle(color: selected ? AppColors.evGreen : AppColors.textDark, fontWeight: FontWeight.w600),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Max Power', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(c.maxPowerKw != null ? '${c.maxPowerKw} kW' : 'Not listed', style: const TextStyle(color: AppColors.textGrey)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pricing', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(
                              c.usageCostRaw?.isNotEmpty == true ? c.usageCostRaw! : 'Check operator app',
                              style: const TextStyle(color: AppColors.textGrey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textGrey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c.address, style: const TextStyle(color: AppColors.textGrey))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Location data: Open Charge Map contributors',
                      style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedBuilder(
                          animation: FavouritesService.instance,
                          builder: (context, _) {
                            final isFav = FavouritesService.instance.isEvFavourite(c.id);
                            return OutlinedButton.icon(
                              onPressed: () => FavouritesService.instance.toggleEv(c),
                              icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, size: 18),
                              label: const Text('Save Favourite'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: AppColors.primaryBlue),
                                foregroundColor: AppColors.primaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              await MapsLauncher.openDirections(lat: c.latitude, lng: c.longitude, label: c.name);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(content: Text('Could not open Google Maps')));
                              }
                            }
                          },
                          icon: const Icon(Icons.navigation_outlined, size: 18),
                          label: const Text('Navigate'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap, {Color color = AppColors.textDark}) {
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(backgroundColor: Colors.white, radius: 18, child: Icon(icon, size: 18, color: color)),
    );
  }
}
