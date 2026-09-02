import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../services/auth_service.dart';
import '../services/fuel_price_service.dart';
import '../services/location_service.dart';
import '../services/reference_prices.dart';
import '../services/saved_route_repository.dart';
import '../services/trip_cost_service.dart';
import '../services/trip_location_service.dart';
import '../services/vehicle_repository.dart';
import '../theme/app_theme.dart';
import 'add_vehicle_dialog.dart';

class TripCalculationScreen extends StatefulWidget {
  final TripMode mode;
  final SavedRoute? initialRoute;
  final bool startEditing;

  const TripCalculationScreen({
    super.key,
    required this.mode,
    this.initialRoute,
    this.startEditing = false,
  });

  @override
  State<TripCalculationScreen> createState() => _TripCalculationScreenState();
}

class _TripCalculationScreenState extends State<TripCalculationScreen> {
  static const _ron95Subsidised = 'RON95 (Subsidised)';
  static const _ron95Unsubsidised = 'RON95 (Unsubsidised)';
  static const _ron97 = 'RON97';
  static const _diesel = 'Diesel';

  final _locationService = TripLocationService();
  TripPlace? _origin;
  TripPlace? _destination;
  String? _vehicleId;
  String? _energyOption;
  JourneyType _journeyType = JourneyType.roundTrip;
  int _travelDays = 5;
  Future<FuelPriceSnapshot>? _fuelPriceFuture;
  TripCalculationResult? _result;
  double? _unitPrice;
  String? _error;
  bool _locating = false;
  bool _calculating = false;
  bool _saving = false;
  bool _autoCalculationScheduled = false;
  late String _savedRouteId;
  late String _savedRouteName;
  late bool _editing;

  bool get _isSavedRouteView => widget.initialRoute != null && !_editing;

  @override
  void initState() {
    super.initState();
    final route = widget.initialRoute;
    _editing = route == null || widget.startEditing;
    _savedRouteId = route?.id ?? '';
    _savedRouteName = route?.name ?? '';
    if (route != null) {
      _origin = route.origin;
      _destination = route.destination;
      _vehicleId = route.vehicleId;
      _energyOption = route.fuelType ?? route.chargingProvider;
      _journeyType = route.journeyType;
      _travelDays = route.travelDaysPerWeek?.clamp(1, 7) ?? 5;
    }
  }

  List<String> _optionsFor(SavedVehicle vehicle) {
    switch (vehicle.powertrain) {
      case VehiclePowertrain.diesel:
        return const [_diesel];
      case VehiclePowertrain.petrol:
        return vehicle.requiresPremiumFuel
            ? const [_ron97]
            : const [_ron95Subsidised, _ron95Unsubsidised, _ron97];
      case VehiclePowertrain.electric:
        return ReferencePrices.evProviderRates.keys.toList();
      case VehiclePowertrain.plugInHybrid:
      case VehiclePowertrain.unsupported:
        return const [];
    }
  }

  double _priceFor(String option, FuelPriceSnapshot prices) {
    switch (option) {
      case _ron95Subsidised:
        return ReferencePrices.ron95Subsidised;
      case _ron95Unsubsidised:
        return prices.ron95;
      case _ron97:
        return prices.ron97;
      case _diesel:
        return prices.diesel;
      default:
        return 0;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final coordinate = await LocationService.getCurrentLocation();
      TripPlace place;
      try {
        place = await _locationService.reverseGeocode(
          coordinate.lat,
          coordinate.lng,
        );
      } on TripLocationException {
        place = TripPlace(
          name: 'Current location',
          address:
              '${coordinate.lat.toStringAsFixed(5)}, ${coordinate.lng.toStringAsFixed(5)}',
          latitude: coordinate.lat,
          longitude: coordinate.lng,
        );
      }
      if (mounted) setState(() => _origin = place);
    } on LocationUnavailableException catch (error) {
      _showError(error.message);
    } on TripLocationException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError(
          'Current location is unavailable. Search for a starting location instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _calculate(SavedVehicle vehicle) async {
    if (_calculating) return;
    if (AuthService.currentUser == null) {
      _showError('You need to be signed in to calculate a route.');
      return;
    }
    if (_origin == null || _destination == null) {
      _showError('Select both a starting location and destination.');
      return;
    }
    if (LocationService.distanceKm(
          AppLatLng(_origin!.latitude, _origin!.longitude),
          AppLatLng(_destination!.latitude, _destination!.longitude),
        ) <
        .05) {
      _showError('Starting location and destination must be different.');
      return;
    }
    if (_energyOption == null) {
      _showError('Select a fuel or charging option.');
      return;
    }
    if (vehicle.powertrain == VehiclePowertrain.plugInHybrid) {
      _showError('Plug-in hybrid vehicles are not supported in this version.');
      return;
    }
    if (vehicle.powertrain == VehiclePowertrain.unsupported) {
      _showError('This vehicle fuel type is not supported.');
      return;
    }

    setState(() {
      _calculating = true;
      _error = null;
      _result = null;
    });
    try {
      final oneWayDistance =
          await _locationService.drivingDistanceKm(_origin!, _destination!);
      late final double price;
      if (vehicle.powertrain == VehiclePowertrain.electric) {
        price = ReferencePrices.evProviderRates[_energyOption] ?? 0;
      } else if (_energyOption == _ron95Subsidised) {
        price = ReferencePrices.ron95Subsidised;
      } else {
        _fuelPriceFuture ??= FuelPriceService.fetchLatest();
        final prices = await _fuelPriceFuture!;
        price = _priceFor(_energyOption!, prices);
      }
      final result = TripCostService.calculate(
        TripCalculationInput(
          mode: widget.mode,
          journeyType: _journeyType,
          oneWayDistanceKm: oneWayDistance,
          vehicle: vehicle,
          unitPrice: price,
          travelDaysPerWeek: widget.mode == TripMode.daily ? _travelDays : null,
        ),
      );
      if (mounted) {
        setState(() {
          _result = result;
          _unitPrice = price;
        });
      }
    } on TripLocationException catch (error) {
      _showError(error.message);
    } on TripCalculationException catch (error) {
      _showError(error.message);
    } on FuelPriceException catch (error) {
      _fuelPriceFuture = null;
      _showError('Current fuel prices are unavailable: ${error.message}');
    } catch (_) {
      _fuelPriceFuture = null;
      _showError(
          'Could not calculate this trip. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<String?> _requestRouteName() async {
    final controller = TextEditingController(
      text: _savedRouteName.isNotEmpty
          ? _savedRouteName
          : (_destination?.name ?? ''),
    );
    String? validationError;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryBlue.withValues(alpha: .1),
            child: const Icon(Icons.bookmark_add_outlined,
                color: AppColors.primaryBlue),
          ),
          title: Text(_savedRouteId.isEmpty ? 'Save Route' : 'Update Route'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Give this trip a short name so it is easy to find.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                decoration: InputDecoration(
                  labelText: 'Route name',
                  hintText: 'University, Office, Weekend Trip…',
                  errorText: validationError,
                  prefixIcon: const Icon(Icons.edit_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  setDialogState(() => validationError = 'Enter a route name');
                  return;
                }
                Navigator.pop(dialogContext, name);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _saveRoute(SavedVehicle vehicle) async {
    if (_result == null || _saving) return;
    final user = AuthService.currentUser;
    if (user == null) {
      _showError('You need to be signed in to save a route.');
      return;
    }
    final name = await _requestRouteName();
    if (name == null || !mounted) return;
    final isElectric = vehicle.powertrain == VehiclePowertrain.electric;
    final route = SavedRoute(
      id: _savedRouteId,
      userId: user.uid,
      name: name,
      origin: _origin!,
      destination: _destination!,
      oneWayDistanceKm: _result!.oneWayDistanceKm,
      vehicleId: vehicle.id,
      vehicleLabelSnapshot: vehicle.label,
      mode: widget.mode,
      journeyType: _journeyType,
      travelDaysPerWeek: widget.mode == TripMode.daily ? _travelDays : null,
      fuelType: isElectric ? null : _energyOption,
      chargingProvider: isElectric ? _energyOption : null,
    );
    setState(() => _saving = true);
    final isNewRoute = route.id.isEmpty;
    try {
      if (isNewRoute) {
        _savedRouteId = await SavedRouteRepository.create(route);
      } else {
        await SavedRouteRepository.update(route);
      }
      if (mounted) {
        setState(() {
          _savedRouteName = name;
          if (widget.initialRoute != null) _editing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 21),
                const SizedBox(width: 10),
                Text(isNewRoute
                    ? 'Route saved successfully.'
                    : 'Saved route updated.'),
              ],
            ),
          ),
        );
      }
    } on SavedRouteRepositoryException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectVehicle(SavedVehicle vehicle) {
    final options = _optionsFor(vehicle);
    setState(() {
      _vehicleId = vehicle.id;
      _energyOption = options.isEmpty ? null : options.first;
      _result = null;
      _unitPrice = null;
      _error = null;
      if (vehicle.powertrain != VehiclePowertrain.electric &&
          _energyOption != _ron95Subsidised) {
        _fuelPriceFuture ??= FuelPriceService.fetchLatest();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.mode.label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<SavedVehicle>>(
        stream: VehicleRepository.watchSavedVehicles(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CenteredMessage(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load saved vehicles',
              message: 'Check your connection and Firestore permissions.',
              action: ElevatedButton(
                  onPressed: () => setState(() {}), child: const Text('Retry')),
            );
          }
          final vehicles = snapshot.data ?? const [];
          if (vehicles.isEmpty) {
            return _CenteredMessage(
              icon: Icons.directions_car_outlined,
              title: 'No saved vehicles',
              message:
                  'Add a vehicle first so Fuel Go can use its saved efficiency.',
              action: ElevatedButton.icon(
                onPressed: () => showAddVehicleDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Vehicle'),
              ),
            );
          }

          SavedVehicle? selected;
          for (final vehicle in vehicles) {
            if (vehicle.id == _vehicleId) {
              selected = vehicle;
            }
          }
          if (selected != null) {
            final options = _optionsFor(selected);
            if (!options.contains(_energyOption)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() =>
                      _energyOption = options.isEmpty ? null : options.first);
                }
              });
            }
            if (widget.initialRoute != null && !_autoCalculationScheduled) {
              _autoCalculationScheduled = true;
              final captured = selected;
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _calculate(captured));
            }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _sectionLabel('ROUTE'),
              const SizedBox(height: 8),
              _PlacePicker(
                label: 'From',
                hint: 'Search starting location',
                value: _origin,
                service: _locationService,
                enabled: _editing,
                onChanged: (place) => setState(() {
                  _origin = place;
                  _result = null;
                }),
              ),
              if (_editing) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _locating ? null : _useCurrentLocation,
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location, size: 18),
                  label: Text(_locating
                      ? 'Finding your location…'
                      : 'Use Current Location'),
                ),
              ],
              const SizedBox(height: 14),
              _PlacePicker(
                label: 'Destination',
                hint: 'Search destination',
                value: _destination,
                service: _locationService,
                enabled: _editing,
                onChanged: (place) => setState(() {
                  _destination = place;
                  _result = null;
                }),
              ),
              const SizedBox(height: 22),
              _sectionLabel('VEHICLE & ENERGY'),
              const SizedBox(height: 8),
              _card(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(selected?.id),
                  initialValue: selected?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Saved vehicle',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                  items: vehicles
                      .map((vehicle) => DropdownMenuItem(
                            value: vehicle.id,
                            child: Text(vehicle.label,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _editing
                      ? (id) {
                          if (id == null) return;
                          _selectVehicle(vehicles
                              .firstWhere((vehicle) => vehicle.id == id));
                        }
                      : null,
                ),
              ),
              if (widget.initialRoute != null &&
                  _vehicleId != null &&
                  selected == null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(
                  message: _editing
                      ? 'The saved vehicle “${widget.initialRoute!.vehicleLabelSnapshot}” was deleted. Select a replacement vehicle to recalculate this route.'
                      : 'The saved vehicle “${widget.initialRoute!.vehicleLabelSnapshot}” was deleted. Choose Update Saved Route to select a replacement.',
                ),
              ],
              if (selected != null) ...[
                const SizedBox(height: 12),
                _VehicleSummary(vehicle: selected),
                if (_optionsFor(selected).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _card(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('${selected.id}:$_energyOption'),
                      initialValue:
                          _optionsFor(selected).contains(_energyOption)
                              ? _energyOption
                              : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            selected.powertrain == VehiclePowertrain.electric
                                ? 'Charging provider'
                                : 'Fuel type',
                        prefixIcon: Icon(
                            selected.powertrain == VehiclePowertrain.electric
                                ? Icons.bolt_outlined
                                : Icons.local_gas_station_outlined),
                      ),
                      items: _optionsFor(selected)
                          .map((option) => DropdownMenuItem(
                              value: option, child: Text(option)))
                          .toList(),
                      onChanged: _editing
                          ? (value) {
                              setState(() {
                                _energyOption = value;
                                _result = null;
                                if (selected!.powertrain !=
                                        VehiclePowertrain.electric &&
                                    value != _ron95Subsidised) {
                                  _fuelPriceFuture ??=
                                      FuelPriceService.fetchLatest();
                                }
                              });
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _PriceStatus(
                    vehicle: selected,
                    option: _energyOption,
                    priceFuture: _fuelPriceFuture,
                    priceFor: _priceFor,
                  ),
                ],
              ],
              const SizedBox(height: 22),
              _sectionLabel('TRIP'),
              const SizedBox(height: 8),
              SegmentedButton<JourneyType>(
                segments: const [
                  ButtonSegment(
                      value: JourneyType.oneWay, label: Text('One Way')),
                  ButtonSegment(
                      value: JourneyType.roundTrip, label: Text('Round Trip')),
                ],
                selected: {_journeyType},
                onSelectionChanged: _editing
                    ? (value) => setState(() {
                          _journeyType = value.first;
                          _result = null;
                        })
                    : null,
              ),
              if (widget.mode == TripMode.daily) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  key: ValueKey(_travelDays),
                  initialValue: _travelDays,
                  decoration: const InputDecoration(
                    labelText: 'Travel days per week',
                    prefixIcon: Icon(Icons.event_repeat_outlined),
                  ),
                  items: List.generate(
                    7,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text(
                          '${index + 1} ${index == 0 ? 'day' : 'days'} per week'),
                    ),
                  ),
                  onChanged: _editing
                      ? (value) => setState(() {
                            _travelDays = value ?? 5;
                            _result = null;
                          })
                      : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _ErrorBanner(message: _error!),
              ],
              if (_editing) ...[
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: selected == null || _calculating
                      ? null
                      : () => _calculate(selected!),
                  icon: _calculating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.calculate_outlined),
                  label: Text(_calculating
                      ? 'Calculating driving route…'
                      : 'Calculate'),
                ),
              ],
              if (_result != null &&
                  selected != null &&
                  _unitPrice != null) ...[
                const SizedBox(height: 22),
                _ResultCard(
                  mode: widget.mode,
                  origin: _origin!,
                  destination: _destination!,
                  vehicle: selected,
                  option: _energyOption!,
                  unitPrice: _unitPrice!,
                  result: _result!,
                ),
                const SizedBox(height: 14),
                if (_editing)
                  ElevatedButton.icon(
                    onPressed: _saving ? null : () => _saveRoute(selected!),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(_savedRouteId.isEmpty
                            ? Icons.bookmark_add_outlined
                            : Icons.save_outlined),
                    label: Text(
                        _savedRouteId.isEmpty ? 'Save Route' : 'Save Changes'),
                  ),
              ],
              if (_isSavedRouteView) ...[
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _editing = true;
                    _error = null;
                  }),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Update Saved Route'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String value) => Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          color: AppColors.textGrey,
          fontWeight: FontWeight.bold,
          letterSpacing: .4,
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: child,
      );
}

class _PlacePicker extends StatefulWidget {
  final String label;
  final String hint;
  final TripPlace? value;
  final TripLocationService service;
  final ValueChanged<TripPlace?> onChanged;
  final bool enabled;

  const _PlacePicker({
    required this.label,
    required this.hint,
    required this.value,
    required this.service,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<TripPlace> _results = const [];
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    final request = ++_request;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final places = await widget.service.searchPlaces(trimmed);
        if (!mounted || request != _request) return;
        setState(() {
          _results = places;
          _error = places.isEmpty ? 'No Malaysian locations found.' : null;
        });
      } on TripLocationException catch (error) {
        if (mounted && request == _request) {
          setState(() {
            _results = const [];
            _error = error.message;
          });
        }
      } finally {
        if (mounted && request == _request) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined,
                color: AppColors.primaryBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textGrey)),
                  Text(widget.value!.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (widget.value!.address != widget.value!.name)
                    Text(widget.value!.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textGrey)),
                ],
              ),
            ),
            if (widget.enabled)
              IconButton(
                tooltip: 'Change ${widget.label.toLowerCase()}',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged(null);
                },
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          enabled: widget.enabled,
          controller: _controller,
          focusNode: _focus,
          onChanged: _search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(_error!,
                style: const TextStyle(fontSize: 11, color: Colors.red)),
          ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: _results
                  .map((place) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined, size: 20),
                        title: Text(place.name),
                        subtitle: Text(place.address,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          _focus.unfocus();
                          setState(() => _results = const []);
                          widget.onChanged(place);
                        },
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _VehicleSummary extends StatelessWidget {
  final SavedVehicle vehicle;
  const _VehicleSummary({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final powertrain = vehicle.powertrain;
    String detail;
    if (powertrain == VehiclePowertrain.electric) {
      detail = vehicle.combinedKwhPer100Km == null
          ? 'Energy efficiency unavailable'
          : '${vehicle.combinedKwhPer100Km!.toStringAsFixed(1)} kWh / 100 km';
    } else if (powertrain == VehiclePowertrain.plugInHybrid) {
      detail = 'Plug-in hybrids are not supported yet';
    } else if (powertrain == VehiclePowertrain.unsupported) {
      detail = 'Unsupported fuel type: ${vehicle.fuelType}';
    } else {
      detail = vehicle.combinedKmL > 0
          ? '${vehicle.combinedKmL.toStringAsFixed(1)} km/L combined'
          : 'Combined fuel efficiency unavailable';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: powertrain == VehiclePowertrain.electric
            ? AppColors.evGreen.withValues(alpha: .08)
            : AppColors.fuelOrange.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(powertrain == VehiclePowertrain.electric
              ? Icons.electric_car
              : Icons.local_gas_station),
          const SizedBox(width: 10),
          Expanded(
              child: Text(detail,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _PriceStatus extends StatelessWidget {
  final SavedVehicle vehicle;
  final String? option;
  final Future<FuelPriceSnapshot>? priceFuture;
  final double Function(String, FuelPriceSnapshot) priceFor;

  const _PriceStatus({
    required this.vehicle,
    required this.option,
    required this.priceFuture,
    required this.priceFor,
  });

  @override
  Widget build(BuildContext context) {
    if (vehicle.powertrain == VehiclePowertrain.electric) {
      final rate = ReferencePrices.evProviderRates[option];
      return Text(
        rate == null
            ? 'Indicative charging rate unavailable'
            : 'Indicative “from” rate: RM ${rate.toStringAsFixed(2)} / kWh · Not a live tariff',
        style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
      );
    }
    if (option == _TripCalculationScreenState._ron95Subsidised) {
      return Text(
        'Configured reference rate: RM ${ReferencePrices.ron95Subsidised.toStringAsFixed(2)} / L',
        style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
      );
    }
    if (priceFuture == null) {
      return const Text('Select a fuel type to load the latest weekly price.',
          style: TextStyle(fontSize: 11, color: AppColors.textGrey));
    }
    return FutureBuilder<FuelPriceSnapshot>(
      future: priceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text('Loading latest weekly fuel price…',
              style: TextStyle(fontSize: 11, color: AppColors.textGrey));
        }
        if (!snapshot.hasData || snapshot.hasError || option == null) {
          return const Text(
              'Latest fuel price unavailable. Calculation will be blocked.',
              style: TextStyle(fontSize: 11, color: Colors.red));
        }
        final price = priceFor(option!, snapshot.data!);
        if (price <= 0) {
          return const Text(
              'Latest fuel price unavailable. Calculation will be blocked.',
              style: TextStyle(fontSize: 11, color: Colors.red));
        }
        return Text(
          'Latest weekly price: RM ${price.toStringAsFixed(2)} / L · ${snapshot.data!.formattedDate}',
          style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  final TripMode mode;
  final TripPlace origin;
  final TripPlace destination;
  final SavedVehicle vehicle;
  final String option;
  final double unitPrice;
  final TripCalculationResult result;

  const _ResultCard({
    required this.mode,
    required this.origin,
    required this.destination,
    required this.vehicle,
    required this.option,
    required this.unitPrice,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    final electric = result.isElectric;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: .15)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: .12),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ESTIMATED COST',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('${origin.name} → ${destination.name}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _row('One-way distance',
              '${result.oneWayDistanceKm.toStringAsFixed(1)} km'),
          _row(mode == TripMode.daily ? 'Daily distance' : 'Total distance',
              '${result.totalDistanceKm.toStringAsFixed(1)} km'),
          _row('Vehicle', vehicle.label),
          _row(
              'Efficiency',
              electric
                  ? '${vehicle.combinedKwhPer100Km!.toStringAsFixed(1)} kWh / 100 km'
                  : '${vehicle.combinedKmL.toStringAsFixed(1)} km/L'),
          _row(electric ? 'Charging provider' : 'Fuel', option),
          _row(electric ? 'Indicative rate' : 'Price',
              'RM ${unitPrice.toStringAsFixed(2)} / ${electric ? 'kWh' : 'L'}'),
          _row(electric ? 'Electricity required' : 'Fuel required',
              '${result.energyRequired.toStringAsFixed(2)} ${electric ? 'kWh' : 'L'}${mode == TripMode.daily ? ' / day' : ''}'),
          const Divider(height: 24),
          if (mode == TripMode.daily) ...[
            _moneyRow('Daily', result.totalCost),
            _moneyRow('Weekly', result.weeklyCost!),
            _moneyRow('Monthly', result.monthlyCost!, large: true),
            const SizedBox(height: 8),
            const Text('Monthly estimate = weekly estimate × 4.33.',
                style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
          ] else
            _moneyRow('Estimated trip cost', result.totalCost, large: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textGrey))),
            const SizedBox(width: 10),
            Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _moneyRow(String label, double value, {bool large = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight:
                            large ? FontWeight.bold : FontWeight.w600))),
            Text('RM ${value.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: large ? 22 : 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
                )),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: const TextStyle(fontSize: 12, color: Colors.red))),
          ],
        ),
      );
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget action;
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: AppColors.textGrey),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppColors.textGrey, height: 1.4)),
              const SizedBox(height: 16),
              SizedBox(width: 220, child: action),
            ],
          ),
        ),
      );
}
