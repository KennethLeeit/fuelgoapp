import 'package:flutter/material.dart';
import '../models/trip_models.dart';
import '../theme/app_theme.dart';

/// A quick, one-off efficiency entry for the Cost Calculator — distinct
/// from AddVehicleDialog, which saves a full vehicle profile (year, make,
/// model) to the account. This just asks for the minimum needed to run a
/// calculation right now, for anyone who doesn't want to save a vehicle at
/// all. Returns a transient [SavedVehicle] (id: 'manual', never persisted
/// to Firestore) that plugs into the exact same calculation pipeline as a
/// real saved vehicle, or null if cancelled.
Future<SavedVehicle?> showManualVehicleDialog(BuildContext context) {
  return showDialog<SavedVehicle>(
    context: context,
    builder: (_) => const _ManualVehicleDialog(),
  );
}

enum _ManualPowertrain { petrol, diesel, electric }

class _ManualVehicleDialog extends StatefulWidget {
  const _ManualVehicleDialog();
  @override
  State<_ManualVehicleDialog> createState() => _ManualVehicleDialogState();
}

class _ManualVehicleDialogState extends State<_ManualVehicleDialog> {
  _ManualPowertrain _powertrain = _ManualPowertrain.petrol;
  final _efficiencyController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _efficiencyController.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_efficiencyController.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = _powertrain == _ManualPowertrain.electric
          ? 'Enter a valid energy use (kWh per 100 km)'
          : 'Enter a valid fuel efficiency (km per litre)');
      return;
    }

    final isElectric = _powertrain == _ManualPowertrain.electric;
    final fuelType = switch (_powertrain) {
      _ManualPowertrain.electric => 'Electric',
      _ManualPowertrain.diesel => 'Diesel',
      _ManualPowertrain.petrol => 'Petrol',
    };

    final vehicle = SavedVehicle(
      id: 'manual',
      year: 0,
      make: 'Manual entry',
      model: '',
      fuelType: fuelType,
      cityKmL: isElectric ? 0 : value,
      highwayKmL: isElectric ? 0 : value,
      combinedKmL: isElectric ? 0 : value,
      combinedKwhPer100Km: isElectric ? value : null,
      isElectric: isElectric,
      isFavourite: false,
    );

    Navigator.of(context).pop(vehicle);
  }

  @override
  Widget build(BuildContext context) {
    final isElectric = _powertrain == _ManualPowertrain.electric;
    return AlertDialog(
      title: const Text('Manually Enter Efficiency'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For a quick one-off calculation without saving a vehicle to your profile.',
              style: TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
            const SizedBox(height: 16),
            const Text('Vehicle type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Petrol'),
                  selected: _powertrain == _ManualPowertrain.petrol,
                  onSelected: (_) => setState(() => _powertrain = _ManualPowertrain.petrol),
                ),
                ChoiceChip(
                  label: const Text('Diesel'),
                  selected: _powertrain == _ManualPowertrain.diesel,
                  onSelected: (_) => setState(() => _powertrain = _ManualPowertrain.diesel),
                ),
                ChoiceChip(
                  label: const Text('Electric'),
                  selected: _powertrain == _ManualPowertrain.electric,
                  onSelected: (_) => setState(() => _powertrain = _ManualPowertrain.electric),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _efficiencyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: isElectric ? 'Energy use' : 'Fuel efficiency',
                suffixText: isElectric ? 'kWh / 100 km' : 'km / litre',
                errorText: _error,
                prefixIcon: Icon(isElectric ? Icons.bolt_outlined : Icons.local_gas_station_outlined),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _submit, child: const Text('Use This')),
      ],
    );
  }
}
