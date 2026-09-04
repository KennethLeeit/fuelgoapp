import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/maps_launcher.dart';
import '../services/favourites_service.dart';
import '../services/ev_operator_utils.dart';
import '../services/osm_reverse_geocoding_service.dart';
import '../widgets/ev_charger_brand_image.dart';
import '../widgets/review_section.dart';
import '../widgets/ui_kit.dart';

class EVChargerDetailScreen extends StatefulWidget {
  final EVCharger charger;
  const EVChargerDetailScreen({super.key, required this.charger});
  @override
  State<EVChargerDetailScreen> createState() => _EVChargerDetailScreenState();
}

class _EVChargerDetailScreenState extends State<EVChargerDetailScreen> {
  String? _selectedConnector;

  // Same on-demand pattern as StationDetailScreen: if this charger
  // arrived with no readable address (common for plain OSM data),
  // resolve one in the background instead of leaving the placeholder up
  // forever. Navigate already works fine off the coordinates regardless.
  String? _resolvedAddress;
  bool _addressLookupDone = false;

  @override
  void initState() {
    super.initState();
    if (widget.charger.connectors.isNotEmpty) {
      _selectedConnector = widget.charger.connectors.first;
    }
    if (widget.charger.hasReadableAddress) {
      _addressLookupDone = true;
    } else {
      final c = widget.charger;
      ReverseGeocodingService.resolveOne(GeocodeTarget(
        id: c.id,
        latitude: c.latitude,
        longitude: c.longitude,
        name: c.name,
        hasReadableAddress: false,
      )).then((address) {
        if (!mounted) return;
        setState(() {
          _resolvedAddress = address;
          _addressLookupDone = true;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.charger;
    final color = colorForName(c.operatorName ?? c.name);
    final tier = chargeSpeedTierFor(c.maxPowerKw);
    final addressText = c.hasReadableAddress
        ? c.address
        : (_resolvedAddress ??
            (_addressLookupDone
                ? 'Street address not listed. Use Navigate for the exact location.'
                : 'Looking up the street address\u2026'));
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EVChargerBrandImage(
                  charger: c,
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      if (c.operatorName != null) ...[
                        const SizedBox(height: 2),
                        Text(normaliseEvOperator(c.operatorName) ?? c.operatorName!,
                            style: const TextStyle(color: AppColors.textGrey)),
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
                      Row(
                        children: [
                          Icon(
                            c.operational == true
                                ? Icons.check_circle
                                : (c.operational == false ? Icons.error : Icons.help_outline),
                            size: 16,
                            color: c.operational == true
                                ? AppColors.evGreen
                                : (c.operational == false ? Colors.red : AppColors.textGrey),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            c.operational == true ? 'Operational' : (c.operational == false ? 'Reported down' : 'Status unknown'),
                            style: TextStyle(
                                color: c.operational == true
                                    ? AppColors.evGreen
                                    : (c.operational == false ? Colors.red : AppColors.textGrey),
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (c.connectors.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const SectionHeader(title: 'Connector Type', padding: EdgeInsets.only(bottom: 10)),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: c.connectors.map((conn) {
                            final selected = conn == _selectedConnector;
                            return ChoiceChip(
                              avatar: Icon(iconForConnector(conn),
                                  size: 16, color: selected ? AppColors.evGreen : AppColors.textGrey),
                              label: Text(conn),
                              selected: selected,
                              onSelected: (_) => setState(() => _selectedConnector = conn),
                              selectedColor: AppColors.evGreen.withOpacity(0.15),
                              labelStyle: TextStyle(
                                  color: selected
                                      ? AppColors.evGreen
                                      : (Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark),
                                  fontWeight: FontWeight.w600),
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
                                if (c.maxPowerKw != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: colorForSpeedTier(tier).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('${c.maxPowerKw} kW \u00b7 ${labelForSpeedTier(tier)}',
                                        style: TextStyle(fontWeight: FontWeight.w600, color: colorForSpeedTier(tier))),
                                  )
                                else
                                  const Text('Not listed', style: TextStyle(color: AppColors.textGrey)),
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
                          Expanded(child: Text(addressText, style: const TextStyle(color: AppColors.textGrey))),
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
                      // Google-Maps-style reviews: average rating + star
                      // breakdown, write/edit-your-own, and everyone else's
                      // reviews for this charger — backed by Firestore so
                      // they're visible across every user of the app.
                      ReviewSection(stationId: c.id, stationType:
                      ReviewStationType.ev, stationName: c.name),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Fixed on top of the whole scroll view (not inside it) so back
          // and favourite stay reachable no matter how far the user has
          // scrolled — previously these scrolled away with the hero image,
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
          ),
        ],
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap, {Color color = AppColors.textDark}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: CircleAvatar(backgroundColor: Colors.transparent, radius: 18, child: Icon(icon, size: 18, color: color)),
      ),
    );
  }
}
