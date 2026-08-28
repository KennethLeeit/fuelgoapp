import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/maps_launcher.dart';
import '../services/favourites_service.dart';

class StationDetailScreen extends StatelessWidget {
  final FuelStation station;
  const StationDetailScreen({super.key, required this.station});

  static const Map<String, IconData> _serviceIcons = {
    'ATM': Icons.local_atm,
    'Toilet': Icons.wc,
    'Shop': Icons.local_convenience_store,
    'Car Wash': Icons.local_car_wash,
    'LPG': Icons.propane_tank_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final s = station;
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [s.brandColor.withOpacity(0.85), s.brandColor.withOpacity(0.4)]),
                  ),
                  child: Center(
                      child: Icon(Icons.local_gas_station, color: Colors.white.withOpacity(0.9), size: 70)),
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
                            final isFav = FavouritesService.instance.isFuelFavourite(s.id);
                            return _circleIconButton(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              () => FavouritesService.instance.toggleFuel(s.id),
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
                  Text(s.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (s.brand != null && s.brand != s.name) ...[
                    const SizedBox(height: 2),
                    Text(s.brand!, style: const TextStyle(color: AppColors.textGrey)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textGrey),
                      const SizedBox(width: 4),
                      Text('${s.distanceKm} km away', style: const TextStyle(color: AppColors.textGrey)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.open24Hours == true ? 'Open 24 Hours' : (s.openingHoursRaw ?? 'Hours not listed on OpenStreetMap'),
                    style: TextStyle(
                        color: s.open24Hours == true ? AppColors.evGreen : AppColors.textGrey,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  const Text('Fuel Available', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Based on typical fuel types sold in Malaysia \u2014 confirm at the pump.',
                      style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: s.fuelTypes.map((f) => Chip(label: Text(f))).toList(),
                  ),
                  if (s.services.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Services', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: s.services.map((serv) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Column(
                            children: [
                              CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFFF1F3F6),
                                  child: Icon(_serviceIcons[serv] ?? Icons.check, color: AppColors.textDark, size: 20)),
                              const SizedBox(height: 4),
                              Text(serv, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 18, color: AppColors.textGrey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.address, style: const TextStyle(color: AppColors.textGrey))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Location data: \u00a9 OpenStreetMap contributors',
                      style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedBuilder(
                          animation: FavouritesService.instance,
                          builder: (context, _) {
                            final isFav = FavouritesService.instance.isFuelFavourite(s.id);
                            return OutlinedButton.icon(
                              onPressed: () => FavouritesService.instance.toggleFuel(s.id),
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
                              await MapsLauncher.openDirections(lat: s.latitude, lng: s.longitude, label: s.name);
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
