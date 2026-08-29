import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/favourites_service.dart';
import '../widgets/station_brand_image.dart';
import 'station_detail_screen.dart';
import 'ev_charger_detail_screen.dart';

/// Favourites (fuel stations and EV chargers) are cached locally in full
/// as soon as they're favourited (see FavouritesService), so this screen
/// reads straight from that local cache — no network request, and a
/// favourite stays visible here regardless of the user's current location
/// or search radius.
class FavouriteScreen extends StatelessWidget {
  const FavouriteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Favourite', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) {
                    final favStations = FavouritesService.instance.fuelStations;
                    final favChargers = FavouritesService.instance.evChargers;
                    final isEmpty = favStations.isEmpty && favChargers.isEmpty;

                    if (isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.favorite_border, size: 60, color: AppColors.textGrey),
                            SizedBox(height: 12),
                            Text('No favourites yet', style: TextStyle(color: AppColors.textGrey)),
                            SizedBox(height: 4),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                'Tap the heart icon on a station or charger to save it here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView(
                      children: [
                        ...favStations.map((s) => _favTile(
                              context: context,
                              leading: StationBrandBadge(station: s, size: 48),
                              title: s.name,
                              subtitle: '${s.distanceKm} km',
                              onTap: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => StationDetailScreen(station: s))),
                              onRemove: () => FavouritesService.instance.toggleFuel(s),
                            )),
                        ...favChargers.map((c) => _favTile(
                              context: context,
                              leading: CircleAvatar(
                                backgroundColor: colorForName(c.operatorName ?? c.name).withValues(alpha: 0.12),
                                child: Icon(Icons.bolt, color: colorForName(c.operatorName ?? c.name)),
                              ),
                              title: c.name,
                              subtitle: '${c.distanceKm} km',
                              onTap: () => Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => EVChargerDetailScreen(charger: c))),
                              onRemove: () => FavouritesService.instance.toggleEv(c),
                            )),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _favTile({
    required BuildContext context,
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.cardBorder)),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          onTap: onTap,
          leading: leading,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
          trailing: IconButton(icon: const Icon(Icons.favorite, color: Colors.red), onPressed: onRemove),
        ),
      ),
    );
  }
}
