import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/maps_launcher.dart';
import '../services/vehicle_preference_service.dart';
import 'station_detail_screen.dart';
import 'ev_charger_detail_screen.dart';
import '../widgets/station_brand_image.dart';

class _MYState {
  final String name;
  final LatLng center;
  const _MYState(this.name, this.center);
}

/// A single Nominatim search result, split into a short primary label and
/// the remaining address for the suggestions dropdown.
class _PlaceSuggestion {
  final String primary;
  final String secondary;
  final double lat;
  final double lon;
  final String displayName;
  const _PlaceSuggestion({
    required this.primary,
    required this.secondary,
    required this.lat,
    required this.lon,
    required this.displayName,
  });
}

// Rough bounding box covering all of Malaysia (Peninsular + Sabah/Sarawak),
// used to bias/restrict Nominatim search results to Malaysia alongside the
// countrycodes=my filter. Format Nominatim expects: left,top,right,bottom.
const String _malaysiaViewbox = '99.5,7.5,119.5,0.8';

// The 13 states of Malaysia plus the Federal Territory of Kuala Lumpur —
// commonly referenced together as "14 states" in everyday usage.
const List<_MYState> _malaysiaStates = [
  _MYState('Johor', LatLng(1.4927, 103.7414)),
  _MYState('Kedah', LatLng(6.1184, 100.3685)),
  _MYState('Kelantan', LatLng(6.1254, 102.2381)),
  _MYState('Melaka', LatLng(2.1896, 102.2501)),
  _MYState('Negeri Sembilan', LatLng(2.7297, 101.9381)),
  _MYState('Pahang', LatLng(3.8077, 103.3260)),
  _MYState('Penang', LatLng(5.4141, 100.3288)),
  _MYState('Perak', LatLng(4.5975, 101.0901)),
  _MYState('Perlis', LatLng(6.4414, 100.1986)),
  _MYState('Sabah', LatLng(5.9804, 116.0735)),
  _MYState('Sarawak', LatLng(1.5535, 110.3593)),
  _MYState('Selangor', LatLng(3.0738, 101.5183)),
  _MYState('Terengganu', LatLng(5.3117, 103.1324)),
  _MYState('W.P. Kuala Lumpur', LatLng(3.1390, 101.6869)),
];

/// Smart Mobility Map — powered by OpenStreetMap (via flutter_map) for
/// tiles, live OSM/Open Charge Map data for markers, and free Nominatim
/// search. No API key required anywhere on this screen.
class SmartMobilityMapScreen extends StatefulWidget {
  final bool embedded;
  const SmartMobilityMapScreen({super.key, this.embedded = true});
  @override
  State<SmartMobilityMapScreen> createState() => _SmartMobilityMapScreenState();
}

class _SmartMobilityMapScreenState extends State<SmartMobilityMapScreen> {
  String _filter = 'Both';

  /// The filter actually applied to markers/lists — forced to match the
  /// vehicle preference when locked to one type, otherwise the user's
  /// manually chosen chip.
  String get _effectiveFilter {
    final mode = VehiclePreferenceService.instance.mode;
    if (mode == VehicleMode.fuelOnly) return 'Fuel Only';
    if (mode == VehicleMode.evOnly) return 'EV Only';
    return _filter;
  }

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _suggestDebounce;
  List<_PlaceSuggestion> _suggestions = [];
  bool _suggestLoading = false;
  bool _searching = false;
  LatLng? _searchResult;
  String? _areaLabel;

  AppLatLng? _me;
  List<FuelStation> _stations = [];
  List<EVCharger> _chargers = [];

  // True while fuel/EV station data is still being fetched. The map is
  // already interactive by the time this matters, so it only drives the
  // small "Loading…" bits, not a full-screen block.
  bool _loading = true;
  bool _fuelFailed = false;
  bool _evFailed = false;
  LatLngBounds? _visibleBounds;

  // Bumped on every _loadNearby() call so that results from a
  // superseded/stale request (e.g. rapid re-search) are ignored when they
  // land out of order.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadNearby(
      {AppLatLng? centerOverride, bool forceRefresh = false}) async {
    final requestId = ++_requestId;

    if (centerOverride != null) {
      // Explicit destination — from search or the state picker. We already
      // know exactly where to go, so skip straight there instead of
      // touching GPS at all.
      setState(() => _me = centerOverride);
      _mapController.move(LatLng(centerOverride.lat, centerOverride.lng), 12.5);
      _fetchStations(centerOverride, requestId, forceRefresh: forceRefresh);
      return;
    }

    // Step 1 — paint *something* right away: the device's last cached
    // fix if the OS has one on hand, otherwise the KL fallback. This
    // never waits on a fresh GPS read or a permission dialog, so the map
    // centers and starts fetching nearby stations essentially instantly.
    final quick = await LocationService.getQuickLocation();
    if (!mounted || requestId != _requestId) return;
    setState(() => _me = quick);
    _mapController.move(LatLng(quick.lat, quick.lng), 12.5);
    _fetchStations(quick, requestId);

    // Step 2 — resolve the precise fix in the background (reusing the one
    // pre-warmed back on the login screen, so this is usually fast) and
    // silently upgrade only if it lands somewhere meaningfully different
    // from the quick guess. If they're close, there's nothing to redo.
    final precise = await LocationService.getCurrentLocation();
    if (!mounted || requestId != _requestId) return;
    if (LocationService.distanceKm(quick, precise) > 0.3) {
      setState(() => _me = precise);
      _mapController.move(LatLng(precise.lat, precise.lng), 12.5);
      _fetchStations(precise, requestId);
    }
  }

  // Fetches fuel stations and EV chargers concurrently (so the wait is
  // the slower of the two, not the sum) starting from `loc` outward. Both
  // services sort nearest-first, so the closest pins land first. Each one
  // paints its own markers onto the already-visible map as soon as it's
  // ready, instead of waiting on each other.
  //
  // Goes through StationCacheService so re-opening this screen (or the
  // Fuel/EV list screens, which share the same cache) near the same spot
  // reuses the last fetch instead of hitting the network again. Pass
  // forceRefresh: true from an explicit user refresh action to bypass it.
  void _fetchStations(AppLatLng loc, int requestId,
      {bool forceRefresh = false}) {
    setState(() {
      _loading = true;
      _fuelFailed = false;
      _evFailed = false;
    });

    var settledCount = 0;
    void onSettled() {
      settledCount++;
      if (settledCount == 2 && mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }

    unawaited(StationCacheService.instance
        .fuel(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh)
        .then((stations) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _stations = stations);
    }).catchError((_) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _fuelFailed = true);
    }).whenComplete(onSettled));

    unawaited(StationCacheService.instance
        .ev(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh)
        .then((chargers) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _chargers = chargers);
    }).catchError((_) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _evFailed = true);
    }).whenComplete(onSettled));
  }

  Future<void> _searchDestination(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _suggestions = [];
    });
    _searchFocusNode.unfocus();
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=1'
        '&countrycodes=my'
        '&viewbox=$_malaysiaViewbox&bounded=1',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      final List<dynamic> results = json.decode(res.body);
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('No results found in Malaysia for that search')));
        }
        return;
      }
      final lat = double.parse(results.first['lat']);
      final lon = double.parse(results.first['lon']);
      final label = results.first['display_name'] as String? ?? query;
      setState(() {
        _searchResult = LatLng(lat, lon);
        _areaLabel = label;
      });
      _mapController.move(LatLng(lat, lon), 14);
      await _loadNearby(centerOverride: AppLatLng(lat, lon));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not search right now. Check your connection.')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // Fires (debounced) on every keystroke to populate the suggestions
  // dropdown, restricted to locations within Malaysia. Kept separate from
  // _searchDestination so a flaky/slow lookup here just quietly yields no
  // suggestions instead of surfacing an error snackbar while typing.
  void _onSearchChanged(String query) {
    _suggestDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // Fires from the very first character — short debounce just to avoid
    // firing mid-keystroke, not to gate on a minimum query length.
    _suggestDebounce = Timer(const Duration(milliseconds: 250), () => _fetchSuggestions(trimmed));
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _suggestLoading = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=6'
        '&countrycodes=my'
        '&viewbox=$_malaysiaViewbox&bounded=1',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      // The field may have changed (or been cleared) while this request was
      // in flight — drop stale results rather than overwriting a newer list.
      if (!mounted || _searchController.text.trim() != query) return;
      final List<dynamic> results = json.decode(res.body);
      setState(() {
        _suggestions = results.map((r) {
          final displayName = r['display_name'] as String? ?? query;
          final parts = displayName.split(',');
          return _PlaceSuggestion(
            primary: parts.first.trim(),
            secondary: parts.skip(1).join(',').trim(),
            lat: double.parse(r['lat']),
            lon: double.parse(r['lon']),
            displayName: displayName,
          );
        }).toList();
      });
    } catch (_) {
      // Silent — this is just live suggestions, not an explicit search.
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _suggestions = []);
      }
    } finally {
      if (mounted) setState(() => _suggestLoading = false);
    }
  }

  Future<void> _selectSuggestion(_PlaceSuggestion s) async {
    _searchController.text = s.primary;
    _searchFocusNode.unfocus();
    setState(() {
      _suggestions = [];
      _searchResult = LatLng(s.lat, s.lon);
      _areaLabel = s.displayName;
    });
    _mapController.move(LatLng(s.lat, s.lon), 14);
    await _loadNearby(centerOverride: AppLatLng(s.lat, s.lon));
  }


  void _pickState() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('Browse by state',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.my_location,
                        color: AppColors.primaryBlue),
                    title: const Text('My current location'),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _areaLabel = null;
                        _searchResult = null;
                        _suggestions = [];
                      });
                      _searchController.clear();
                      _loadNearby();
                    },
                  ),
                  const Divider(height: 1),
                  ..._malaysiaStates.map((s) => ListTile(
                        leading: const Icon(Icons.map_outlined,
                            color: AppColors.textGrey),
                        title: Text(s.name),
                        trailing: _areaLabel == s.name
                            ? const Icon(Icons.check,
                                color: AppColors.primaryBlue)
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _areaLabel = s.name;
                            _searchResult = null;
                            _suggestions = [];
                          });
                          _searchController.clear();
                          _mapController.move(s.center, 10.5);
                          _loadNearby(
                              centerOverride: AppLatLng(
                                  s.center.latitude, s.center.longitude));
                        },
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _zoom(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + delta).clamp(3.0, 18.0));
  }

  bool _inView(double lat, double lng) {
    final bounds = _visibleBounds;
    if (bounds == null)
      return true; // before first camera event, show everything fetched
    return bounds.contains(LatLng(lat, lng));
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_me != null) {
      markers.add(
        Marker(
          point: LatLng(_me!.lat, _me!.lng),
          width: 24,
          height: 24,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4)
              ],
            ),
          ),
        ),
      );
    }

    if (_effectiveFilter != 'EV Only') {
      for (final s in _stations) {
        if (!_inView(s.latitude, s.longitude)) continue;
        markers.add(
          Marker(
            point: LatLng(s.latitude, s.longitude),
            width: 46,
            height: 46,
            child: GestureDetector(
              onTap: () => _showPlaceSheet(
                name: s.name,
                distance: '${s.distanceKm} km',
                color: AppColors.fuelOrange,
                icon: Icons.local_gas_station,
                lat: s.latitude,
                lng: s.longitude,
                fuelStation: s,
                onView: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => StationDetailScreen(station: s))),
              ),
              child: StationBrandBadge(station: s, size: 42, mapMarker: true),
            ),
          ),
        );
      }
    }

    if (_effectiveFilter != 'Fuel Only') {
      for (final c in _chargers) {
        if (!_inView(c.latitude, c.longitude)) continue;
        markers.add(
          Marker(
            point: LatLng(c.latitude, c.longitude),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _showPlaceSheet(
                name: c.name,
                distance: '${c.distanceKm} km',
                color: AppColors.evGreen,
                icon: Icons.bolt,
                lat: c.latitude,
                lng: c.longitude,
                onView: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EVChargerDetailScreen(charger: c))),
              ),
              child: const _MapPin(icon: Icons.bolt, color: AppColors.evGreen),
            ),
          ),
        );
      }
    }

    if (_searchResult != null) {
      markers.add(
        Marker(
          point: _searchResult!,
          width: 40,
          height: 40,
          child: const _MapPin(icon: Icons.place, color: Colors.red),
        ),
      );
    }

    return markers;
  }

  void _showPlaceSheet({
    required String name,
    required String distance,
    required Color color,
    required IconData icon,
    required double lat,
    required double lng,
    required VoidCallback onView,
    FuelStation? fuelStation,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                fuelStation == null
                    ? CircleAvatar(
                        backgroundColor: color.withOpacity(0.15),
                        child: Icon(icon, color: color))
                    : StationBrandBadge(
                        station: fuelStation,
                        size: 42,
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(distance,
                          style: const TextStyle(
                              color: AppColors.textGrey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onView();
                    },
                    child: const Text('View details'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      MapsLauncher.openDirections(
                          lat: lat, lng: lng, label: name);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VehiclePreferenceService.instance,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final visibleFuel = _stations
        .where((s) =>
            _effectiveFilter != 'EV Only' && _inView(s.latitude, s.longitude))
        .toList();
    final visibleEv = _chargers
        .where((c) =>
            _effectiveFilter != 'Fuel Only' && _inView(c.latitude, c.longitude))
        .toList();
    final nearestFuel = visibleFuel.isNotEmpty
        ? visibleFuel.first
        : (_stations.isNotEmpty ? _stations.first : null);
    final nearestEv = visibleEv.isNotEmpty
        ? visibleEv.first
        : (_chargers.isNotEmpty ? _chargers.first : null);
    final bothFailed = _fuelFailed && _evFailed;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 24),
                  const Text('Smart Mobility Map',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 20, color: AppColors.textGrey),
                    onPressed: () => _loadNearby(
                      centerOverride: _me,
                      forceRefresh: true,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: _searchDestination,
                      decoration: InputDecoration(
                        hintText: 'Search a location in Malaysia...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searching || _suggestLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              )
                            : (_searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    tooltip: 'Clear and use my location',
                                    onPressed: () {
                                      _suggestDebounce?.cancel();
                                      _searchController.clear();
                                      setState(() {
                                        _suggestions = [];
                                        _areaLabel = null;
                                        _searchResult = null;
                                      });
                                      _searchFocusNode.unfocus();
                                      _loadNearby();
                                    },
                                  )
                                : null),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.cardBorder)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _pickState,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder)),
                      child: const Icon(Icons.tune),
                    ),
                  ),
                ],
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = _suggestions[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, color: AppColors.textGrey),
                        title: Text(s.primary, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: s.secondary.isNotEmpty
                            ? Text(s.secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))
                            : null,
                        onTap: () => _selectSuggestion(s),
                      );
                    },
                  ),
                ),
              ],
              if (_areaLabel != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place_outlined,
                        size: 14, color: AppColors.textGrey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text('Showing: $_areaLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textGrey)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final vp = VehiclePreferenceService.instance;
                  if (vp.isLocked) {
                    final isFuelMode = vp.mode == VehicleMode.fuelOnly;
                    final color =
                        isFuelMode ? AppColors.fuelOrange : AppColors.evGreen;
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border:
                                  Border.all(color: color.withOpacity(0.3))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  isFuelMode
                                      ? Icons.local_gas_station
                                      : Icons.bolt,
                                  size: 14,
                                  color: color),
                              const SizedBox(width: 6),
                              Text(
                                  isFuelMode
                                      ? 'Fuel Stations Only'
                                      : 'EV Chargers Only',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: color)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                              'Change in Profile \u2192 Vehicle Preference',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textGrey)),
                        ),
                        TextButton.icon(
                          onPressed: _pickState,
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('State',
                              style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4)),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      _filterChip('Both'),
                      const SizedBox(width: 8),
                      _filterChip('Fuel Only'),
                      const SizedBox(width: 8),
                      _filterChip('EV Only'),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _pickState,
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label:
                            const Text('State', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4)),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(LocationService.fallback.lat,
                              LocationService.fallback.lng),
                          initialZoom: 12.5,
                          minZoom: 3,
                          maxZoom: 18,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                          onMapEvent: (evt) {
                            setState(() => _visibleBounds =
                                _mapController.camera.visibleBounds);
                          },
                          onTap: (tapPosition, point) {
                            if (_suggestions.isNotEmpty || _searchFocusNode.hasFocus) {
                              _searchFocusNode.unfocus();
                              setState(() => _suggestions = []);
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.example.fuelgo_app',
                          ),
                          MarkerLayer(markers: _buildMarkers()),
                          RichAttributionWidget(
                            attributions: [
                              TextSourceAttribution(
                                'OpenStreetMap contributors',
                                onTap: () => launchUrl(Uri.parse(
                                    'https://openstreetmap.org/copyright')),
                              ),
                              TextSourceAttribution(
                                'CARTO',
                                onTap: () => launchUrl(Uri.parse(
                                    'https://carto.com/attributions')),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Column(
                          children: [
                            _zoomButton(Icons.add, () => _zoom(1)),
                            const SizedBox(height: 8),
                            _zoomButton(Icons.remove, () => _zoom(-1)),
                          ],
                        ),
                      ),
                      if (_loading)
                        const Positioned(
                          top: 8,
                          left: 8,
                          child: _LoadingPill(label: 'Finding nearby places…'),
                        ),
                      if (!_loading && bothFailed)
                        Container(
                          color: Colors.white,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.wifi_off_rounded,
                                    color: AppColors.textGrey, size: 32),
                                const SizedBox(height: 8),
                                const Text('Could not load nearby places',
                                    style:
                                        TextStyle(color: AppColors.textGrey)),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                    onPressed: () =>
                                        _loadNearby(centerOverride: _me),
                                    child: const Text('Retry')),
                              ],
                            ),
                          ),
                        ),
                      if (!_loading &&
                          !bothFailed &&
                          (_fuelFailed || _evFailed))
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Text(
                                _fuelFailed
                                    ? 'Could not refresh nearby stations. Check your connection and try again.'
                                    : 'EV charger data unavailable right now',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Nearest Around You',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: () {
                  final cards = <Widget>[];
                  if (_effectiveFilter != 'EV Only') {
                    cards.add(_nearestCard(
                      icon: Icons.local_gas_station,
                      color: AppColors.fuelOrange,
                      title: 'Fuel Station',
                      subtitle: nearestFuel?.name ??
                          (_loading ? 'Loading\u2026' : 'None nearby'),
                      distance: nearestFuel != null
                          ? '${nearestFuel.distanceKm} km'
                          : '',
                      onView: nearestFuel == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => StationDetailScreen(
                                      station: nearestFuel))),
                    ));
                  }
                  if (_effectiveFilter != 'Fuel Only') {
                    cards.add(_nearestCard(
                      icon: Icons.bolt,
                      color: AppColors.evGreen,
                      title: 'EV Charger',
                      subtitle: nearestEv?.name ??
                          (_loading ? 'Loading\u2026' : 'None nearby'),
                      distance:
                          nearestEv != null ? '${nearestEv.distanceKm} km' : '',
                      onView: nearestEv == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => EVChargerDetailScreen(
                                      charger: nearestEv))),
                    ));
                  }
                  final spaced = <Widget>[];
                  for (var i = 0; i < cards.length; i++) {
                    spaced.add(Expanded(child: cards[i]));
                    if (i != cards.length - 1)
                      spaced.add(const SizedBox(width: 12));
                  }
                  return spaced;
                }(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: AppColors.textDark),
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = label),
      selectedColor: AppColors.primaryBlue,
      labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.textDark,
          fontWeight: FontWeight.w600,
          fontSize: 12),
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.cardBorder),
    );
  }

  Widget _nearestCard(
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required String distance,
      required VoidCallback? onView}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(distance,
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                side: const BorderSide(color: AppColors.primaryBlue),
                foregroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('View'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small non-blocking chip shown while fuel/EV data is still loading —
/// the map underneath is already visible and interactive at this point.
class _LoadingPill extends StatelessWidget {
  final String label;
  const _LoadingPill({required this.label});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 4),
            ]),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 6),
            Text(label,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textGrey)),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPin({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}
