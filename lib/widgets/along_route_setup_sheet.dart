import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../services/location_service.dart';
import '../services/reference_prices.dart';
import '../services/trip_location_service.dart';
import '../services/vehicle_repository.dart';
import '../theme/app_theme.dart';
import 'trip_place_picker.dart';

class AlongRouteSetupSheet extends StatefulWidget {
  final AlongRouteLaunchData? initial;

  const AlongRouteSetupSheet({super.key, this.initial});

  @override
  State<AlongRouteSetupSheet> createState() => _AlongRouteSetupSheetState();
}

class _AlongRouteSetupSheetState extends State<AlongRouteSetupSheet> {
  final _locationService = TripLocationService();
  TripPlace? _origin;
  TripPlace? _destination;
  String? _vehicleId;
  String? _energyOption;
  bool _locating = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _origin = widget.initial?.origin;
    _destination = widget.initial?.destination;
    _vehicleId = widget.initial?.vehicle?.id;
    _energyOption = widget.initial?.energyOption;
  }

  List<String> _optionsFor(SavedVehicle vehicle) {
    switch (vehicle.powertrain) {
      case VehiclePowertrain.electric:
        return ReferencePrices.evProviderRates.keys.toList(growable: false);
      case VehiclePowertrain.diesel:
        return const ['Diesel'];
      case VehiclePowertrain.petrol:
        return vehicle.requiresPremiumFuel
            ? const ['RON97']
            : const ['RON95 (Subsidised)', 'RON95', 'RON97'];
      case VehiclePowertrain.plugInHybrid:
      case VehiclePowertrain.unsupported:
        return const [];
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final position = await LocationService.getSharedCurrentLocation();
      final reverse = await _locationService.reverseGeocode(
        position.lat,
        position.lng,
      );
      final place = TripPlace(
        name: 'Current location',
        address: reverse.address,
        latitude: position.lat,
        longitude: position.lng,
      );
      if (mounted) setState(() => _origin = place);
    } on TripLocationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on LocationUnavailableException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Current location is unavailable. Search for an origin instead.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _showRoute(SavedVehicle? vehicle) async {
    if (_origin == null || _destination == null) {
      setState(() => _error = 'Select both an origin and destination.');
      return;
    }
    if (LocationService.distanceKm(
          AppLatLng(_origin!.latitude, _origin!.longitude),
          AppLatLng(_destination!.latitude, _destination!.longitude),
        ) <
        .05) {
      setState(() => _error = 'Origin and destination must be different.');
      return;
    }
    if (vehicle != null && _optionsFor(vehicle).isEmpty) {
      setState(() => _error =
          'This vehicle powertrain is not supported for recommendations.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final route = await _locationService.drivingRoute(
        _origin!,
        _destination!,
      );
      if (!route.hasGeometry) {
        throw const TripLocationException(
            'The route provider did not return a route line. Try again.');
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        AlongRouteLaunchData(
          origin: _origin!,
          destination: _destination!,
          route: route,
          vehicle: vehicle,
          energyOption: vehicle == null ? null : _energyOption,
        ),
      );
    } on TripLocationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: StreamBuilder<List<SavedVehicle>>(
          stream: VehicleRepository.watchSavedVehicles(),
          builder: (context, snapshot) {
            final vehicles = snapshot.data ?? const <SavedVehicle>[];
            SavedVehicle? selected;
            for (final vehicle in vehicles) {
              if (vehicle.id == _vehicleId) selected = vehicle;
            }
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.route_outlined,
                            color: AppColors.primaryBlue),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Find stops along a route',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose two Malaysian locations. A vehicle is optional and only improves the recommendation order.',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  TripPlacePicker(
                    label: 'From',
                    hint: 'Search starting location',
                    value: _origin,
                    service: _locationService,
                    onChanged: (value) => setState(() => _origin = value),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _useCurrentLocation,
                    icon: _locating
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(_locating
                        ? 'Finding your location…'
                        : 'Use Current Location'),
                  ),
                  const SizedBox(height: 12),
                  TripPlacePicker(
                    label: 'Destination',
                    hint: 'Search destination',
                    value: _destination,
                    service: _locationService,
                    onChanged: (value) => setState(() => _destination = value),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String?>(
                    initialValue: selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle (optional)',
                      prefixIcon: Icon(Icons.directions_car_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('No vehicle preference')),
                      ...vehicles.map((vehicle) => DropdownMenuItem<String?>(
                            value: vehicle.id,
                            child: Text(vehicle.label,
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (id) {
                      final vehicle = id == null
                          ? null
                          : vehicles.firstWhere((item) => item.id == id);
                      final options = vehicle == null
                          ? const <String>[]
                          : _optionsFor(vehicle);
                      setState(() {
                        _vehicleId = id;
                        _energyOption = options.isEmpty ? null : options.first;
                      });
                    },
                  ),
                  if (selected != null && _optionsFor(selected).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          _optionsFor(selected).contains(_energyOption)
                              ? _energyOption
                              : _optionsFor(selected).first,
                      decoration: InputDecoration(
                        labelText:
                            selected.powertrain == VehiclePowertrain.electric
                                ? 'Preferred provider'
                                : 'Preferred fuel',
                      ),
                      items: _optionsFor(selected)
                          .map((option) => DropdownMenuItem(
                              value: option, child: Text(option)))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _energyOption = value),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : () => _showRoute(selected),
                      icon: _loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.route_outlined),
                      label:
                          Text(_loading ? 'Calculating route…' : 'Show Route'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
