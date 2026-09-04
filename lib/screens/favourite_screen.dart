import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/favourites_service.dart';
import '../widgets/station_brand_image.dart';
import '../widgets/ev_charger_brand_image.dart';
import '../widgets/ui_kit.dart';
import 'station_detail_screen.dart';
import 'ev_charger_detail_screen.dart';

enum _FavFilter { all, fuel, ev }

/// Favourites (fuel stations and EV chargers) are cached locally in full
/// as soon as they're favourited (see FavouritesService), so this screen
/// reads straight from that local cache — no network request, and a
/// favourite stays visible here regardless of the user's current location
/// or search radius.
///
/// A favourite synced from another device (an id from Firestore with no
/// locally-cached object yet) is filled in by
/// FavouritesService.reconcileMissing, which looks it up directly by id —
/// no location or radius involved, so every saved favourite shows up
/// regardless of how far it is from the user right now. That happens
/// automatically after login, and again whenever this screen's refresh
/// button is tapped.
class FavouriteScreen extends StatefulWidget {
  const FavouriteScreen({super.key});
  @override
  State<FavouriteScreen> createState() => _FavouriteScreenState();
}

class _FavouriteScreenState extends State<FavouriteScreen> {
  _FavFilter _filter = _FavFilter.all;
  bool _reconciling = false;

  Future<void> _refresh() async {
    setState(() => _reconciling = true);
    await FavouritesService.instance.reconcileMissing();
    if (mounted) setState(() => _reconciling = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageTitle(
                title: 'Favourite',
                trailing: IconButton(
                  icon: _reconciling
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, color: AppColors.textGrey),
                  tooltip: 'Refresh',
                  onPressed: _reconciling ? null : _refresh,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _filterChip('All', _FavFilter.all),
                  _filterChip('Fuel Stations', _FavFilter.fuel),
                  _filterChip('EV Chargers', _FavFilter.ev),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: AnimatedBuilder(
                  animation: FavouritesService.instance,
                  builder: (context, _) {
                    final allStations = FavouritesService.instance.fuelStations;
                    final allChargers = FavouritesService.instance.evChargers;
                    final favStations = _filter == _FavFilter.ev ? const <FuelStation>[] : allStations;
                    final favChargers = _filter == _FavFilter.fuel ? const <EVCharger>[] : allChargers;
                    final isEmpty = favStations.isEmpty && favChargers.isEmpty;

                    final missingCount = (_filter != _FavFilter.ev ? FavouritesService.instance.missingFuelCount : 0) +
                        (_filter != _FavFilter.fuel ? FavouritesService.instance.missingEvCount : 0);

                    if (isEmpty) {
                      final hasAnyFavourites = allStations.isNotEmpty || allChargers.isNotEmpty || missingCount > 0;
                      return AppEmptyState(
                        icon: Icons.favorite_border,
                        title: hasAnyFavourites ? 'No favourites in this filter' : 'No favourites yet',
                        message: hasAnyFavourites
                            ? 'Try a different filter, or tap the heart icon on a station or charger to save it here.'
                            : 'Tap the heart icon on a station or charger to save it here.',
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (missingCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppNoticeBanner(
                              message: FavouritesService.instance.hasUnresolvableOcmFavourites
                                  ? '$missingCount favourite${missingCount == 1 ? '' : 's'} '
                                      'couldn\'t be loaded \u2014 one or more was saved from a source '
                                      'that now needs an API key to look up again. Refreshing won\'t '
                                      'fix this one.'
                                  : '$missingCount favourite${missingCount == 1 ? '' : 's'} couldn\'t be loaded '
                                      'right now \u2014 tap refresh to try again.',
                            ),
                          ),
                        Expanded(
                          child: ListView(
                            children: [
                              ...favStations.map((s) => _favTile(
                                    context: context,
                                    leading: StationBrandBadge(station: s, size: 48),
                                    title: s.name,
                                    subtitle: '${s.distanceKm} km',
                                    onTap: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => StationDetailScreen(station: s))),
                                    onRemove: () => FavouritesService.instance.toggleFuel(s),
                                  )),
                              ...favChargers.map((c) => _favTile(
                                    context: context,
                                    leading: EVChargerBrandBadge(charger: c, size: 48),
                                    title: c.name,
                                    subtitle: '${c.distanceKm} km',
                                    onTap: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => EVChargerDetailScreen(charger: c))),
                                    onRemove: () => FavouritesService.instance.toggleEv(c),
                                  )),
                            ],
                          ),
                        ),
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

  Widget _filterChip(String label, _FavFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.primaryBlue,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textDark,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.cardBorder),
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
