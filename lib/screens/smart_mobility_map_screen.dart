import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../models/trip_models.dart';
import '../services/location_service.dart';
import '../services/station_cache_service.dart';
import '../services/auth_service.dart';
import '../services/maps_launcher.dart';
import '../services/vehicle_preference_service.dart';
import '../services/trip_location_service.dart';
import '../services/route_station_recommendation_service.dart';
import '../services/reference_prices.dart';
import 'station_detail_screen.dart';
import 'ev_charger_detail_screen.dart';
import '../widgets/station_brand_image.dart';
import '../widgets/ev_charger_brand_image.dart';
import '../widgets/along_route_setup_sheet.dart';

enum _MapDiscoveryMode { nearby, alongRoute }

class _MYState {
  final String name;
  final LatLng center;
  const _MYState(this.name, this.center);
}

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
/// tiles and live OSM/Open Charge Map data for markers. Malaysian place
/// search is shared with the Trip Calculator through the protected routing
/// backend.
class SmartMobilityMapScreen extends StatefulWidget {
  final bool embedded;
  final AlongRouteLaunchData? initialAlongRoute;
  const SmartMobilityMapScreen({
    super.key,
    this.embedded = true,
    this.initialAlongRoute,
  });
  @override
  State<SmartMobilityMapScreen> createState() => _SmartMobilityMapScreenState();
}

class _SmartMobilityMapScreenState extends State<SmartMobilityMapScreen> {
  String _filter = 'Both';
  _MapDiscoveryMode _discoveryMode = _MapDiscoveryMode.nearby;
  AlongRouteLaunchData? _alongRoute;
  double _corridorKm = RouteStationRecommendationService.normalCorridorKm;
  List<AlongRouteRecommendation<FuelStation>> _fuelRecommendations = const [];
  List<AlongRouteRecommendation<EVCharger>> _evRecommendations = const [];

  /// The filter actually applied to markers/lists — forced to match the
  /// vehicle preference when locked to one type, otherwise the user's
  /// manually chosen chip.
  String get _effectiveFilter {
    if (_discoveryMode == _MapDiscoveryMode.alongRoute) {
      final energyOption = _alongRoute?.energyOption;
      if (energyOption != null) {
        if (ReferencePrices.evProviderRates.containsKey(energyOption)) {
          return 'EV Only';
        }
        return 'Fuel Only';
      }
      final powertrain = _alongRoute?.vehicle?.powertrain;
      if (powertrain == VehiclePowertrain.electric) return 'EV Only';
      if (powertrain == VehiclePowertrain.petrol ||
          powertrain == VehiclePowertrain.diesel) {
        return 'Fuel Only';
      }
      return _filter;
    }
    final mode = VehiclePreferenceService.instance.mode;
    if (mode == VehicleMode.fuelOnly) return 'Fuel Only';
    if (mode == VehicleMode.evOnly) return 'EV Only';
    return _filter;
  }

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final TripLocationService _tripLocationService = TripLocationService();
  Timer? _suggestDebounce;
  List<TripPlace> _suggestions = [];
  bool _suggestLoading = false;
  bool _searching = false;
  LatLng? _searchResult;
  String? _areaLabel;

  AppLatLng? _me;
  AppLatLng? _gpsLocation;
  AppLatLng? _nearbyCenter;
  List<FuelStation> _stations = [];
  List<EVCharger> _chargers = [];
  List<FuelStation> _nearbyStations = [];
  List<EVCharger> _nearbyChargers = [];

  // True while fuel/EV station data is still being fetched. The map is
  // already interactive by the time this matters, so it only drives the
  // small "Loading…" bits, not a full-screen block.
  bool _loading = true;
  bool _fuelFailed = false;
  bool _evFailed = false;
  LatLngBounds? _visibleBounds;

  // Set if that first resolution genuinely failed (permission denied,
  // location services off, etc). Shown with a retry action instead of
  // silently guessing a location.
  String? _locationError;

  // Debounces _visibleBounds updates from onMapEvent. flutter_map fires
  // many move events per second during a single pan/zoom/fling gesture —
  // setState-ing (and thus rebuilding every marker) on each one is what
  // made the map feel sluggish while interacting with it. Coalescing
  // rapid events into a single update ~120ms after the gesture settles
  // keeps marker filtering responsive without rebuilding on every frame.
  Timer? _boundsDebounce;

  // Bumped on every _loadNearby() call so that results from a
  // superseded/stale request (e.g. rapid re-search) are ignored when they
  // land out of order.
  int _requestId = 0;

  // Bumped on every _fetchStations() call — including the Step 1 vs
  // Step 2 pair inside a single _loadNearby. _requestId alone is not
  // enough: those two fetches share a requestId, so a stale Step 1
  // completion can clear (or keep) the loading flag for Step 2.
  int _fetchGeneration = 0;
  Timer? _loadingCeiling;

  // True once the user taps the "tap to open" placeholder shown in place
  // of the map. FlutterMap only paints tiles reliably once something has
  // triggered a real rebuild after mount (observed via the header's
  // refresh button working when the map itself didn't render on first
  // load) — gating behind an explicit tap, then running that exact same
  // refresh, sidesteps the issue instead of trying to render an empty map
  // immediately on arrival.
  bool _mapActivated = false;

  // Every call site that wants to move/fit the map's camera goes through
  // these instead of calling _mapController directly, since the controller
  // isn't attached to anything until _mapActivated flips — calling it
  // earlier (e.g. during the automatic location resolution in initState)
  // would throw. Skipping it is harmless: the map's initialCenter already
  // reads the latest _me/_alongRoute state, so it opens correctly
  // centered regardless of whether these fired while inactive.
  void _moveMapIfActive(LatLng point, double zoom) {
    if (!_mapActivated) return;
    _mapController.move(point, zoom);
  }

  void _fitCameraIfActive(CameraFit fit) {
    if (!_mapActivated) return;
    _mapController.fitCamera(fit);
  }

  @override
  void initState() {
    super.initState();
    final launch = widget.initialAlongRoute;
    if (launch != null) {
      _discoveryMode = _MapDiscoveryMode.alongRoute;
      _alongRoute = launch;
      _me = AppLatLng(launch.origin.latitude, launch.origin.longitude);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadAlongRoute(forceRefresh: true));
    } else {
      _loadNearby();
    }
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _boundsDebounce?.cancel();
    _loadingCeiling?.cancel();
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
      setState(() {
        _me = centerOverride;
        _nearbyCenter = centerOverride;
        _locationError = null;
      });
      _moveMapIfActive(LatLng(centerOverride.lat, centerOverride.lng), 12.5);
      _fetchStations(centerOverride, requestId, forceRefresh: forceRefresh);
      return;
    }

    // Use the same fresh GPS path as the Trip Calculator. Ranking from a
    // cached fix and then moving the map to a fresher fix could make this
    // screen disagree with the Home EV list about which charger is nearest.
    AppLatLng current;
    try {
      current = await LocationService.getSharedCurrentLocation();
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _locationError = e is LocationUnavailableException
            ? e.message
            : 'Could not determine your location.';
      });
      return;
    }
    if (!mounted || requestId != _requestId) return;
    unawaited(AuthService.updateLastLocation(current.lat, current.lng));
    setState(() {
      _me = current;
      _gpsLocation = current;
      _nearbyCenter = current;
      _locationError = null;
    });
    _moveMapIfActive(LatLng(current.lat, current.lng), 12.5);
    _fetchStations(current, requestId, forceRefresh: forceRefresh);
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
    final fetchId = ++_fetchGeneration;
    _loadingCeiling?.cancel();
    setState(() {
      _loading = true;
      _fuelFailed = false;
      _evFailed = false;
      _stations = const [];
      _chargers = const [];
    });

    // Hard ceiling: if a fuel/EV future never settles (or completion
    // tracking gets tangled again), drop the loading pill so the map
    // isn't stuck on "Finding nearby places…" forever.
    _loadingCeiling = Timer(const Duration(seconds: 12), () {
      if (!mounted || fetchId != _fetchGeneration) return;
      setState(() => _loading = false);
    });

    var settledCount = 0;
    void finishIfDone() {
      settledCount++;
      if (settledCount < 2) return;
      if (!mounted || fetchId != _fetchGeneration || requestId != _requestId) {
        return;
      }
      _loadingCeiling?.cancel();
      setState(() => _loading = false);
    }

    unawaited(StationCacheService.instance
        .fuel(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh)
        .then((stations) {
      if (!mounted || fetchId != _fetchGeneration || requestId != _requestId) {
        return;
      }
      setState(() {
        _stations = stations;
        _nearbyStations = stations;
        _fuelFailed = false;
      });
    }).catchError((_) {
      if (!mounted || fetchId != _fetchGeneration || requestId != _requestId) {
        return;
      }
      setState(() => _fuelFailed = true);
    }).whenComplete(finishIfDone));

    unawaited(StationCacheService.instance
        .ev(loc, radiusKm: 12, limit: 40, forceRefresh: forceRefresh)
        .then((chargers) {
      if (!mounted || fetchId != _fetchGeneration || requestId != _requestId) {
        return;
      }
      setState(() {
        _chargers = chargers;
        _nearbyChargers = chargers;
        _evFailed = false;
      });
    }).catchError((_) {
      if (!mounted || fetchId != _fetchGeneration || requestId != _requestId) {
        return;
      }
      setState(() => _evFailed = true);
    }).whenComplete(finishIfDone));
  }

  Future<void> _openAlongRouteSetup() async {
    final result = await showDialog<AlongRouteLaunchData>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
          child: AlongRouteSetupSheet(initial: _alongRoute),
        ),
      ),
    );
    if (result == null || !mounted) {
      if (_alongRoute == null)
        setState(() => _discoveryMode = _MapDiscoveryMode.nearby);
      return;
    }
    setState(() {
      _discoveryMode = _MapDiscoveryMode.alongRoute;
      _alongRoute = result;
      _me = AppLatLng(result.origin.latitude, result.origin.longitude);
      _visibleBounds = null;
      _fuelRecommendations = const [];
      _evRecommendations = const [];
      _stations = const [];
      _chargers = const [];
    });
    await _loadAlongRoute(forceRefresh: true);
  }

  Future<void> _loadAlongRoute({bool forceRefresh = false}) async {
    final launch = _alongRoute;
    if (launch == null) {
      await _openAlongRouteSetup();
      return;
    }
    final requestId = ++_requestId;
    final nearbyCenter = _nearbyCenter;
    final beginsAtNearbyCenter = nearbyCenter != null &&
        LocationService.distanceKm(
              nearbyCenter,
              AppLatLng(launch.origin.latitude, launch.origin.longitude),
            ) <=
            2;
    final nearbyFuelSeed = beginsAtNearbyCenter
        ? List<FuelStation>.of(_nearbyStations)
        : const <FuelStation>[];
    final nearbyEvSeed = beginsAtNearbyCenter
        ? List<EVCharger>.of(_nearbyChargers)
        : const <EVCharger>[];
    setState(() {
      _loading = true;
      _fuelFailed = false;
      _evFailed = false;
      _fuelRecommendations = const [];
      _evRecommendations = const [];
      _stations = const [];
      _chargers = const [];
    });
    try {
      final futures = <Future<void>>[];
      if (_effectiveFilter != 'EV Only') {
        futures.add(
            RouteStationRecommendationService.fetchFuelCandidates(launch.route)
                .then((items) {
          if (!mounted || requestId != _requestId) return;
          final ranked = RouteStationRecommendationService.rankFuel(
            launch.route,
            [...items, ...nearbyFuelSeed],
            selectedFuel: launch.energyOption,
            corridorKm: _corridorKm,
          );
          setState(() {
            _fuelRecommendations = ranked;
            _stations = ranked.map((item) => item.place).toList();
          });
        }).catchError((_) {
          if (mounted && requestId == _requestId)
            setState(() => _fuelFailed = true);
        }));
      }
      if (_effectiveFilter != 'Fuel Only') {
        futures.add(RouteStationRecommendationService.fetchEvCandidates(
          launch.route,
          forceRefreshOrigin: forceRefresh,
        ).then((items) {
          if (!mounted || requestId != _requestId) return;
          final ranked = RouteStationRecommendationService.rankEv(
            launch.route,
            [...items, ...nearbyEvSeed],
            preferredProvider: launch.energyOption,
            corridorKm: _corridorKm,
          );
          setState(() {
            _evRecommendations = ranked;
            _chargers = ranked.map((item) => item.place).toList();
          });
        }).catchError((_) {
          if (mounted && requestId == _requestId)
            setState(() => _evFailed = true);
        }));
      }
      await Future.wait(futures);
      if (!mounted || requestId != _requestId) return;
      _fitAlongRoute(launch.route);
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  void _fitAlongRoute(DrivingRoute route) {
    if (!route.hasGeometry) return;
    final points = route.geometry
        .map((point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    _fitCameraIfActive(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.all(42),
    ));
  }

  Future<void> _searchDestination(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _suggestions = [];
    });
    _searchFocusNode.unfocus();
    try {
      final results = await _tripLocationService.searchPlaces(query);
      if (results.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No results found in Malaysia for that search')));
        }
        return;
      }
      final place = results.first;
      final lat = place.latitude;
      final lon = place.longitude;
      final label = place.address;
      setState(() {
        _searchResult = LatLng(lat, lon);
        _areaLabel = label;
      });
      _moveMapIfActive(LatLng(lat, lon), 14);
      await _loadNearby(
        centerOverride: AppLatLng(lat, lon),
        forceRefresh: true,
      );
    } on TripLocationException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
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
    if (trimmed.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _suggestDebounce = Timer(
        const Duration(milliseconds: 450), () => _fetchSuggestions(trimmed));
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _suggestLoading = true);
    try {
      final results = await _tripLocationService.searchPlaces(query);
      // The field may have changed (or been cleared) while this request was
      // in flight — drop stale results rather than overwriting a newer list.
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() => _suggestions = results);
    } catch (_) {
      // Silent — this is just live suggestions, not an explicit search.
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _suggestions = []);
      }
    } finally {
      if (mounted) setState(() => _suggestLoading = false);
    }
  }

  Future<void> _selectSuggestion(TripPlace s) async {
    _searchController.text = s.name;
    _searchFocusNode.unfocus();
    setState(() {
      _suggestions = [];
      _searchResult = LatLng(s.latitude, s.longitude);
      _areaLabel = s.address;
    });
    _moveMapIfActive(LatLng(s.latitude, s.longitude), 14);
    await _loadNearby(
      centerOverride: AppLatLng(s.latitude, s.longitude),
      forceRefresh: true,
    );
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
                          _moveMapIfActive(s.center, 10.5);
                          _loadNearby(
                              centerOverride: AppLatLng(
                                  s.center.latitude, s.center.longitude),
                              forceRefresh: true);
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

  AlongRouteRecommendation<FuelStation>? _fuelRecommendationFor(String id) {
    for (final recommendation in _fuelRecommendations) {
      if (recommendation.place.id == id) return recommendation;
    }
    return null;
  }

  AlongRouteRecommendation<EVCharger>? _evRecommendationFor(String id) {
    for (final recommendation in _evRecommendations) {
      if (recommendation.place.id == id) return recommendation;
    }
    return null;
  }

  String _routeDistanceLabel(double kilometres) {
    // Report a conservative upper-bound band instead of false metre-level
    // precision from two separate map datasets.
    final upperBound = ((kilometres * 2).ceil() / 2).clamp(.5, 10.0);
    return 'Within ${upperBound.toStringAsFixed(1)} km';
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    final primaryMarker = _discoveryMode == _MapDiscoveryMode.alongRoute &&
            _alongRoute != null
        ? AppLatLng(_alongRoute!.origin.latitude, _alongRoute!.origin.longitude)
        : _gpsLocation;
    if (primaryMarker != null) {
      markers.add(
        Marker(
          point: LatLng(primaryMarker.lat, primaryMarker.lng),
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
      final stationMarkers = _discoveryMode == _MapDiscoveryMode.alongRoute
          ? _stations.take(12)
          : _stations;
      for (final s in stationMarkers) {
        if (!_inView(s.latitude, s.longitude)) continue;
        final recommendation = _fuelRecommendationFor(s.id);
        markers.add(
          Marker(
            point: LatLng(s.latitude, s.longitude),
            width: 46,
            height: 46,
            child: RepaintBoundary(
              child: GestureDetector(
                onTap: () => _showPlaceSheet(
                  name: s.name,
                  distance: recommendation == null
                      ? '${s.distanceKm} km'
                      : '${_routeDistanceLabel(recommendation.distanceFromRouteKm)} · ${recommendation.reason}',
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
          ),
        );
      }
    }

    if (_effectiveFilter != 'Fuel Only') {
      final chargerMarkers = _discoveryMode == _MapDiscoveryMode.alongRoute
          ? _chargers.take(12)
          : _chargers;
      for (final c in chargerMarkers) {
        if (!_inView(c.latitude, c.longitude)) continue;
        final recommendation = _evRecommendationFor(c.id);
        markers.add(
          Marker(
            point: LatLng(c.latitude, c.longitude),
            width: 40,
            height: 40,
            child: RepaintBoundary(
              child: GestureDetector(
                onTap: () => _showPlaceSheet(
                  name: c.name,
                  distance: recommendation == null
                      ? '${c.distanceKm} km'
                      : '${_routeDistanceLabel(recommendation.distanceFromRouteKm)} · ${recommendation.reason}',
                  color: AppColors.evGreen,
                  icon: Icons.bolt,
                  lat: c.latitude,
                  lng: c.longitude,
                  evCharger: c,
                  onView: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => EVChargerDetailScreen(charger: c))),
                ),
                child:
                    EVChargerBrandBadge(charger: c, size: 40, mapMarker: true),
              ),
            ),
          ),
        );
      }
    }

    if (_discoveryMode == _MapDiscoveryMode.nearby && _searchResult != null) {
      markers.add(
        Marker(
          point: _searchResult!,
          width: 40,
          height: 40,
          child: const _MapPin(icon: Icons.place, color: Colors.red),
        ),
      );
    }

    if (_discoveryMode == _MapDiscoveryMode.alongRoute && _alongRoute != null) {
      markers.add(
        Marker(
          point: LatLng(_alongRoute!.destination.latitude,
              _alongRoute!.destination.longitude),
          width: 42,
          height: 42,
          child: const _MapPin(icon: Icons.flag, color: Colors.red),
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
    EVCharger? evCharger,
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
                fuelStation != null
                    ? StationBrandBadge(
                        station: fuelStation,
                        size: 42,
                      )
                    : evCharger != null
                        ? EVChargerBrandBadge(
                            charger: evCharger,
                            size: 42,
                          )
                        : CircleAvatar(
                            backgroundColor: color.withOpacity(0.15),
                            child: Icon(icon, color: color)),
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

  // Shown instead of the map while the very first location resolution is
  // in flight, or if it genuinely failed — there's no hardcoded fallback
  // city, so until we have a real coordinate there's nothing honest to
  // center a map on.
  Widget _buildLocationGate(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _locationError != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_off_outlined,
                          size: 48, color: AppColors.textGrey),
                      const SizedBox(height: 16),
                      Text(_locationError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textGrey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _locationError = null;
                          });
                          _loadNearby();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _pickState,
                        child: const Text('Or pick a state instead'),
                      ),
                      TextButton.icon(
                        onPressed: _openAlongRouteSetup,
                        icon: const Icon(Icons.route_outlined),
                        label: const Text('Plan an Along Route search'),
                      ),
                    ],
                  )
                : const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Finding your location\u2026',
                          style: TextStyle(color: AppColors.textGrey)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    if (_me == null) {
      return _buildLocationGate(context);
    }
    final nearestFuel = _discoveryMode == _MapDiscoveryMode.alongRoute
        ? (_fuelRecommendations.isEmpty
            ? null
            : _fuelRecommendations.first.place)
        : (_nearbyStations.isNotEmpty ? _nearbyStations.first : null);
    final nearestEv = _discoveryMode == _MapDiscoveryMode.alongRoute
        ? (_evRecommendations.isEmpty ? null : _evRecommendations.first.place)
        : (_nearbyChargers.isNotEmpty ? _nearbyChargers.first : null);
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
                  widget.embedded
                      ? const SizedBox(width: 24)
                      : IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                  const Text('Smart Mobility Map',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 20, color: AppColors.textGrey),
                    onPressed: _discoveryMode == _MapDiscoveryMode.alongRoute
                        ? () => _loadAlongRoute(forceRefresh: true)
                        : () => _loadNearby(
                              centerOverride: _nearbyCenter,
                              forceRefresh: true,
                            ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MapDiscoveryMode>(
                  segments: const [
                    ButtonSegment(
                      value: _MapDiscoveryMode.nearby,
                      icon: Icon(Icons.near_me_outlined, size: 18),
                      label: Text('Nearby'),
                    ),
                    ButtonSegment(
                      value: _MapDiscoveryMode.alongRoute,
                      icon: Icon(Icons.route_outlined, size: 18),
                      label: Text('Along Route'),
                    ),
                  ],
                  selected: {_discoveryMode},
                  onSelectionChanged: (selection) {
                    final next = selection.first;
                    if (next == _MapDiscoveryMode.alongRoute) {
                      setState(() => _discoveryMode = next);
                      if (_alongRoute == null) {
                        _openAlongRouteSetup();
                      } else {
                        _loadAlongRoute();
                      }
                    } else {
                      setState(() {
                        _discoveryMode = next;
                        _fuelRecommendations = const [];
                        _evRecommendations = const [];
                        _me = _nearbyCenter ?? _gpsLocation ?? _me;
                        _stations = List<FuelStation>.of(_nearbyStations);
                        _chargers = List<EVCharger>.of(_nearbyChargers);
                        _visibleBounds = null;
                      });
                      _loadNearby(
                        centerOverride: _nearbyCenter,
                        forceRefresh: true,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 14),
              if (_discoveryMode == _MapDiscoveryMode.nearby) ...[
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
                              borderSide: const BorderSide(
                                  color: AppColors.cardBorder)),
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
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).dividerColor)),
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
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).dividerColor)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _suggestions.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined,
                              color: AppColors.textGrey),
                          title: Text(s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: s.address.isNotEmpty
                              ? Text(s.address,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11))
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
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: .25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.route_outlined,
                          color: AppColors.primaryBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _alongRoute == null
                                  ? 'Choose a route'
                                  : '${_alongRoute!.origin.name} → ${_alongRoute!.destination.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (_alongRoute != null)
                              Text(
                                '${_alongRoute!.route.distanceKm.toStringAsFixed(1)} km driving route',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textGrey),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _openAlongRouteSetup,
                        child: Text(_alongRoute == null ? 'Choose' : 'Edit'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Search area: ',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.textGrey)),
                    ChoiceChip(
                      label: const Text('5 km'),
                      selected: _corridorKm ==
                          RouteStationRecommendationService.normalCorridorKm,
                      onSelected: (_) {
                        setState(() => _corridorKm =
                            RouteStationRecommendationService.normalCorridorKm);
                        _loadAlongRoute();
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('10 km'),
                      selected: _corridorKm ==
                          RouteStationRecommendationService.wideCorridorKm,
                      onSelected: (_) {
                        setState(() => _corridorKm =
                            RouteStationRecommendationService.wideCorridorKm);
                        _loadAlongRoute();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Also includes nearby places within 12 km of your start and destination.',
                  style: TextStyle(fontSize: 10, color: AppColors.textGrey),
                ),
              ],
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final vp = VehiclePreferenceService.instance;
                  final routeVehicle = _alongRoute?.vehicle;
                  if (_discoveryMode == _MapDiscoveryMode.alongRoute &&
                      routeVehicle != null) {
                    final showsEv = _effectiveFilter == 'EV Only';
                    final color =
                        showsEv ? AppColors.evGreen : AppColors.fuelOrange;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withValues(alpha: .3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              showsEv
                                  ? Icons.electric_car_outlined
                                  : Icons.directions_car_outlined,
                              color: color,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(routeVehicle.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                Text(
                                  showsEv
                                      ? 'Showing EV chargers for this saved vehicle'
                                      : 'Showing fuel stations for this saved vehicle',
                                  style: const TextStyle(
                                      fontSize: 10, color: AppColors.textGrey),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.verified_outlined, color: color, size: 19),
                        ],
                      ),
                    );
                  }
                  if (_discoveryMode == _MapDiscoveryMode.nearby &&
                      vp.isLocked) {
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
                      if (_discoveryMode == _MapDiscoveryMode.nearby) ...[
                        const Spacer(),
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
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: !_mapActivated
                      ? _buildMapPlaceholder()
                      : Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: LatLng(_me!.lat, _me!.lng),
                          initialZoom: 12.5,
                          minZoom: 3,
                          maxZoom: 18,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all,
                          ),
                          onMapEvent: (evt) {
                            _boundsDebounce?.cancel();
                            _boundsDebounce =
                                Timer(const Duration(milliseconds: 120), () {
                              if (!mounted) return;
                              setState(() => _visibleBounds =
                                  _mapController.camera.visibleBounds);
                            });
                          },
                          onTap: (tapPosition, point) {
                            if (_suggestions.isNotEmpty ||
                                _searchFocusNode.hasFocus) {
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
                          if (_discoveryMode == _MapDiscoveryMode.alongRoute &&
                              _alongRoute?.route.hasGeometry == true)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _alongRoute!.route.geometry
                                      .map((point) => LatLng(
                                          point.latitude, point.longitude))
                                      .toList(growable: false),
                                  color: AppColors.primaryBlue,
                                  strokeWidth: 5,
                                ),
                              ],
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
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _LoadingPill(
                            label:
                                _discoveryMode == _MapDiscoveryMode.alongRoute
                                    ? 'Finding places along route…'
                                    : 'Finding nearby places…',
                          ),
                        ),
                      if (!_loading && bothFailed)
                        Container(
                          color: Theme.of(context).cardColor,
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
                                    onPressed: _discoveryMode ==
                                            _MapDiscoveryMode.alongRoute
                                        ? () =>
                                            _loadAlongRoute(forceRefresh: true)
                                        : () => _loadNearby(
                                            centerOverride: _nearbyCenter,
                                            forceRefresh: true),
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
                              padding: const EdgeInsets.only(
                                  left: 10, top: 6, bottom: 6, right: 2),
                              decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _fuelFailed
                                          ? 'Could not refresh nearby stations. Check your connection and try again.'
                                          : 'EV charger data unavailable right now',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.refresh, size: 18),
                                    tooltip: 'Retry',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _discoveryMode ==
                                            _MapDiscoveryMode.alongRoute
                                        ? () =>
                                            _loadAlongRoute(forceRefresh: true)
                                        : () => _loadNearby(
                                            centerOverride: _nearbyCenter,
                                            forceRefresh: true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                  _discoveryMode == _MapDiscoveryMode.alongRoute
                      ? 'Recommended Along Route'
                      : 'Nearest Around You',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: () {
                  final cards = <Widget>[];
                  if (_effectiveFilter != 'EV Only') {
                    cards.add(_nearestCard(
                      icon: Icons.local_gas_station,
                      color: AppColors.fuelOrange,
                      title: _discoveryMode == _MapDiscoveryMode.alongRoute
                          ? 'Recommended Fuel Station'
                          : 'Fuel Station',
                      subtitle: nearestFuel?.name ??
                          (_loading ? 'Loading\u2026' : 'None nearby'),
                      distance: nearestFuel == null
                          ? ''
                          : _fuelRecommendationFor(nearestFuel.id) != null
                              ? _routeDistanceLabel(
                                  _fuelRecommendationFor(nearestFuel.id)!
                                      .distanceFromRouteKm)
                              : '${nearestFuel.distanceKm} km',
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
                      title: _discoveryMode == _MapDiscoveryMode.alongRoute
                          ? 'Recommended EV Charger'
                          : 'EV Charger',
                      subtitle: nearestEv?.name ??
                          (_loading ? 'Loading\u2026' : 'None nearby'),
                      distance: nearestEv == null
                          ? ''
                          : _evRecommendationFor(nearestEv.id) != null
                              ? _routeDistanceLabel(
                                  _evRecommendationFor(nearestEv.id)!
                                      .distanceFromRouteKm)
                              : '${nearestEv.distanceKm} km',
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

  // Shown in place of the actual map until tapped. FlutterMap needs a real
  // rebuild pulse after mount to reliably paint tiles (mirrors why the
  // header's refresh button visibly "fixes" a blank map) — so the tap here
  // both activates the map AND fires the same refresh call that button
  // uses, instead of trying to render an untouched map immediately.
  Widget _buildMapPlaceholder() {
    return Material(
      color: const Color(0xFFE9EEF5),
      child: InkWell(
        onTap: () {
          setState(() => _mapActivated = true);
          if (_discoveryMode == _MapDiscoveryMode.alongRoute) {
            _loadAlongRoute(forceRefresh: true);
          } else {
            _loadNearby(centerOverride: _nearbyCenter, forceRefresh: true);
          }
        },
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: AppColors.primaryBlue, shape: BoxShape.circle),
                  child: const Icon(Icons.map_outlined, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 12),
                Text('Tap to open the map',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)),
                const SizedBox(height: 4),
                const Text('Your location is ready \u2014 tap to load the map',
                    style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark),
        ),
      ),
    );
  }

  Widget _filterChip(String label) {
    final selected = _filter == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _filter = label);
        if (_discoveryMode == _MapDiscoveryMode.alongRoute) {
          _loadAlongRoute();
        }
      },
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
          color: color.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25))),
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
            color: Theme.of(context).cardColor,
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
