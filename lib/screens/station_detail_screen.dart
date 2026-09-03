import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/maps_launcher.dart';
import '../services/favourites_service.dart';
import '../services/osm_reverse_geocoding_service.dart';
import '../widgets/station_brand_image.dart';
import '../widgets/review_section.dart';

class StationDetailScreen extends StatefulWidget {
  final FuelStation station;
  const StationDetailScreen({super.key, required this.station});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  // Filled in the background if the station arrived with no readable
  // address at all (common for plain OSM data with no addr:* tags) —
  // Navigate already works fine off the coordinates regardless of this;
  // this is purely to replace the "not listed" placeholder with a real
  // street address once one is found. Null while unresolved; distinguish
  // "still looking" from "gave up" with [_lookupDone].
  String? _resolvedAddress;
  bool _lookupDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.station.hasReadableAddress) {
      _lookupDone = true;
    } else {
      final s = widget.station;
      ReverseGeocodingService.resolveOne(GeocodeTarget(
        id: s.id,
        latitude: s.latitude,
        longitude: s.longitude,
        name: s.name,
        hasReadableAddress: false,
      )).then((address) {
        if (!mounted) return;
        setState(() {
          _resolvedAddress = address;
          _lookupDone = true;
        });
      });
    }
  }

  static const Map<String, IconData> _serviceIcons = {
    'ATM': Icons.local_atm,
    'Toilet': Icons.wc,
    'Shop': Icons.local_convenience_store,
    'Car Wash': Icons.local_car_wash,
    'LPG': Icons.propane_tank_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.station;
    final addressText = s.hasReadableAddress
        ? s.address
        : (_resolvedAddress ??
            (_lookupDone
                ? 'Street address not listed. Use Navigate for the exact location.'
                : 'Looking up the street address\u2026'));
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No fixed height here anymore — StationBrandImage sizes
                // itself (via AspectRatio) to whichever photo it ends up
                // showing, so the full image is always visible and this
                // area is only as tall as that photo actually needs.
                StationBrandImage(station: s),
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
                              addressText,
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
                      // Google-Maps-style reviews: average rating + star
                      // breakdown, write/edit-your-own, and everyone else's
                      // reviews for this station — backed by Firestore so
                      // they're visible across every user of the app.
                      ReviewSection(stationId: s.id, stationType: ReviewStationType.fuel),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Fixed on top of the whole scroll view (not inside it) so back
          // and favourite stay reachable no matter how far the user has
          // scrolled — previously these scrolled away with the hero photo,
          // meaning a trip back up was needed just to go back or favourite.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap,
      {Color color = AppColors.textDark}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: CircleAvatar(
            backgroundColor: Colors.transparent,
            radius: 18,
            child: Icon(icon, size: 18, color: color)),
      ),
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
