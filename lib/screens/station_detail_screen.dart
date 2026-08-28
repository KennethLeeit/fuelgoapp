import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/maps_launcher.dart';
import '../services/favourites_service.dart';
import '../widgets/station_brand_image.dart';

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
                    gradient: LinearGradient(colors: [
                      s.displayBrandColor.withValues(alpha: 0.85),
                      s.displayBrandColor.withValues(alpha: 0.4)
                    ]),
                  ),
                  child: StationBrandImage(station: s),
                ),
                SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _circleIconButton(Icons.arrow_back_ios_new,
                            () => Navigator.pop(context)),
                        AnimatedBuilder(
                          animation: FavouritesService.instance,
                          builder: (context, _) {
                            final isFav = FavouritesService.instance
                                .isFuelFavourite(s.id);
                            return _circleIconButton(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              () => FavouritesService.instance.toggleFuel(s),
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
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.sell_outlined,
                          size: 15, color: AppColors.textGrey),
                      const SizedBox(width: 5),
                      Text(
                        'Brand: ${s.brand?.trim().isNotEmpty == true ? s.brand! : 'Not specified'}',
                        style: const TextStyle(color: AppColors.textGrey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: AppColors.textGrey),
                      const SizedBox(width: 4),
                      Text('${s.distanceKm} km away',
                          style: const TextStyle(color: AppColors.textGrey)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.open24Hours == true
                        ? 'Open 24 Hours'
                        : (s.openingHoursRaw ?? 'Hours not verified'),
                    style: TextStyle(
                        color: s.open24Hours == true
                            ? AppColors.evGreen
                            : AppColors.textGrey,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  const Text('Fuel Available',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (s.fuelTypes.isEmpty)
                    const _MissingInfoCard(
                      icon: Icons.local_gas_station_outlined,
                      title: 'No fuel details available',
                      message:
                          'Fuel types have not been confirmed for this station.',
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children:
                          s.fuelTypes.map((f) => Chip(label: Text(f))).toList(),
                    ),
                  const SizedBox(height: 20),
                  const Text('Services & facilities',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (s.services.isEmpty)
                    const _MissingInfoCard(
                      icon: Icons.storefront_outlined,
                      title: 'No service details available',
                      message:
                          'Facilities have not been confirmed for this station.',
                    )
                  else
                    Wrap(
                      spacing: 14,
                      runSpacing: 12,
                      children: s.services.map((serv) {
                        return Padding(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFFF1F3F6),
                                  child: Icon(
                                      _serviceIcons[serv] ?? Icons.check,
                                      color: AppColors.textDark,
                                      size: 20)),
                              const SizedBox(height: 4),
                              Text(serv, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 18, color: AppColors.textGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.hasReadableAddress
                              ? s.address
                              : 'Street address not listed. Use Navigate for the exact location.',
                          style: const TextStyle(color: AppColors.textGrey),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => MapsLauncher.openLocation(
                        lat: s.latitude,
                        lng: s.longitude,
                        label: s.name,
                      ),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('View exact location on map'),
                    ),
                  ),
                  if (s.website != null && s.website!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: () async {
                        final raw = s.website!.trim();
                        final uri = Uri.tryParse(
                            raw.startsWith('http') ? raw : 'https://$raw');
                        if (uri != null) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.language, size: 18),
                      label: const Text('Official station website'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: AnimatedBuilder(
                          animation: FavouritesService.instance,
                          builder: (context, _) {
                            final isFav = FavouritesService.instance
                                .isFuelFavourite(s.id);
                            return OutlinedButton.icon(
                              onPressed: () =>
                                  FavouritesService.instance.toggleFuel(s),
                              icon: Icon(
                                  isFav
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  size: 18),
                              label: const Text('Save Favourite'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(
                                    color: AppColors.primaryBlue),
                                foregroundColor: AppColors.primaryBlue,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
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
                              await MapsLauncher.openDirections(
                                  lat: s.latitude,
                                  lng: s.longitude,
                                  label: s.name);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'Could not open Google Maps')));
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

  Widget _circleIconButton(IconData icon, VoidCallback onTap,
      {Color color = AppColors.textDark}) {
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(
          backgroundColor: Colors.white,
          radius: 18,
          child: Icon(icon, size: 18, color: color)),
    );
  }
}

class _MissingInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MissingInfoCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 19, color: AppColors.textGrey),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(message,
                    style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppColors.textGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
