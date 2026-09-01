import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/vehicle_api_service.dart';
import '../services/vehicle_repository.dart';

/// Shows the "Add Vehicle" dialog and returns the [VehicleFuelEconomy]
/// the user confirmed, or `null` if they cancelled.
Future<VehicleFuelEconomy?> showAddVehicleDialog(BuildContext context) {
  return showDialog<VehicleFuelEconomy>(
    context: context,
    builder: (_) => const AddVehicleDialog(),
  );
}

class AddVehicleDialog extends StatefulWidget {
  const AddVehicleDialog({super.key});

  @override
  State<AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<AddVehicleDialog> {
  List<VehicleMenuItem> _years = [];
  List<VehicleMenuItem> _makes = [];
  List<VehicleMenuItem> _models = [];
  List<VehicleMenuItem> _options = [];

  VehicleMenuItem? _selectedYear;
  VehicleMenuItem? _selectedMake;
  VehicleMenuItem? _selectedModel;
  VehicleMenuItem? _selectedOption;

  bool _loadingYears = true;
  bool _loadingMakes = false;
  bool _loadingModels = false;
  bool _loadingOptions = false;
  bool _loadingResult = false;
  bool _saving = false;

  VehicleFuelEconomy? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadYears();
  }

  Future<void> _loadYears() async {
    setState(() {
      _loadingYears = true;
      _error = null;
    });
    try {
      final years = await VehicleApiService.getYears();
      // Newest year first is friendlier to scroll through.
      years.sort((a, b) => b.text.compareTo(a.text));
      setState(() => _years = years);
    } on VehicleApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingYears = false);
    }
  }

  Future<void> _onYearChanged(VehicleMenuItem? year) async {
    setState(() {
      _selectedYear = year;
      _selectedMake = null;
      _selectedModel = null;
      _selectedOption = null;
      _makes = [];
      _models = [];
      _options = [];
      _result = null;
      _error = null;
    });
    if (year == null) return;
    setState(() => _loadingMakes = true);
    try {
      final makes = await VehicleApiService.getMakes(year.value);
      setState(() => _makes = makes);
    } on VehicleApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingMakes = false);
    }
  }

  Future<void> _onMakeChanged(VehicleMenuItem? make) async {
    setState(() {
      _selectedMake = make;
      _selectedModel = null;
      _selectedOption = null;
      _models = [];
      _options = [];
      _result = null;
      _error = null;
    });
    if (make == null || _selectedYear == null) return;
    setState(() => _loadingModels = true);
    try {
      final models =
      await VehicleApiService.getModels(_selectedYear!.value, make.value);
      setState(() => _models = models);
    } on VehicleApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _onModelChanged(VehicleMenuItem? model) async {
    setState(() {
      _selectedModel = model;
      _selectedOption = null;
      _options = [];
      _result = null;
      _error = null;
    });
    if (model == null || _selectedYear == null || _selectedMake == null) {
      return;
    }
    setState(() => _loadingOptions = true);
    try {
      final options = await VehicleApiService.getOptions(
        _selectedYear!.value,
        _selectedMake!.value,
        model.value,
      );
      setState(() => _options = options);
      // Most models resolve to a single configuration — skip straight
      // to the result instead of making the user pick a list of one.
      if (options.length == 1) {
        _selectedOption = options.first;
        await _fetchResult(options.first);
      }
    } on VehicleApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _onOptionChanged(VehicleMenuItem? option) async {
    setState(() {
      _selectedOption = option;
      _result = null;
      _error = null;
    });
    if (option == null) return;
    await _fetchResult(option);
  }

  Future<void> _fetchResult(VehicleMenuItem option) async {
    setState(() => _loadingResult = true);
    try {
      final details = await VehicleApiService.getVehicleDetails(option.value);
      setState(() => _result = details);
    } on VehicleApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingResult = false);
    }
  }

  Future<void> _saveAndClose() async {
    if (_result == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await VehicleRepository.addVehicle(_result!);
      if (mounted) Navigator.of(context).pop(_result);
    } on VehicleRepositoryException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Could not save the vehicle. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.directions_car_filled_outlined,
                      color: AppColors.primaryBlue),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Add Vehicle',
                        style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textGrey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter your car\'s year, brand and model to look up its EPA fuel efficiency.',
                style: TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MenuDropdown<VehicleMenuItem>(
                        label: 'Year',
                        loading: _loadingYears,
                        value: _selectedYear,
                        items: _years,
                        itemLabel: (i) => i.text,
                        onChanged: _onYearChanged,
                      ),
                      const SizedBox(height: 12),
                      _MenuDropdown<VehicleMenuItem>(
                        label: 'Brand',
                        loading: _loadingMakes,
                        value: _selectedMake,
                        items: _makes,
                        itemLabel: (i) => i.text,
                        enabled: _selectedYear != null,
                        onChanged: _onMakeChanged,
                      ),
                      const SizedBox(height: 12),
                      _MenuDropdown<VehicleMenuItem>(
                        label: 'Model',
                        loading: _loadingModels,
                        value: _selectedModel,
                        items: _models,
                        itemLabel: (i) => i.text,
                        enabled: _selectedMake != null,
                        onChanged: _onModelChanged,
                      ),
                      if (_options.length > 1) ...[
                        const SizedBox(height: 12),
                        _MenuDropdown<VehicleMenuItem>(
                          label: 'Trim / configuration',
                          loading: _loadingOptions,
                          value: _selectedOption,
                          items: _options,
                          itemLabel: (i) => i.text,
                          enabled: true,
                          onChanged: _onOptionChanged,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDEDED),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 18, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_loadingResult) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        ),
                      ],
                      if (_result != null) ...[
                        const SizedBox(height: 16),
                        _FuelEconomyResultCard(result: _result!),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: (_result == null || _saving)
                          ? null
                          : _saveAndClose,
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                          : const Text('Add Vehicle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuDropdown<T> extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;

  const _MenuDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.loading = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textDark)),
        const SizedBox(height: 6),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: loading
              ? const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Loading…', style: TextStyle(color: AppColors.textGrey)),
            ],
          )
              : DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              hint: Text(
                enabled ? 'Select $label' : 'Select $label above first',
                style: const TextStyle(color: AppColors.textGrey, fontSize: 13),
              ),
              items: items
                  .map((item) => DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel(item),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
              ))
                  .toList(),
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _FuelEconomyResultCard extends StatelessWidget {
  final VehicleFuelEconomy result;
  const _FuelEconomyResultCard({required this.result});

  // 1 US gallon = 3.785411784 L, 1 mile = 1.609344 km.
  // km per US gallon / L per gallon = km/L per mpg.
  static const _mpgToKmL = 1.609344 / 3.785411784;

  static double _kmL(int mpg) => mpg * _mpgToKmL;

  @override
  Widget build(BuildContext context) {
    final unit = result.isElectric ? 'km/L (eq)' : 'km/L';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${result.year} ${result.make} ${result.model}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            [result.fuelType, result.trans, result.drive]
                .where((s) => s.isNotEmpty)
                .join(' • '),
            style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MpgStat(label: 'City', value: _kmL(result.cityMpg), unit: unit),
              _MpgStat(
                  label: 'Highway',
                  value: _kmL(result.highwayMpg),
                  unit: unit),
              _MpgStat(
                  label: 'Combined',
                  value: _kmL(result.combinedMpg),
                  unit: unit),
            ],
          ),
          if (result.combinedKwhPer100Miles != null) ...[
            const SizedBox(height: 10),
            Text(
              'Electricity use: ${result.combinedKwhPer100Miles!.toStringAsFixed(1)} kWh / 100 mi',
              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
            ),
          ],
        ],
      ),
    );
  }
}

class _MpgStat extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  const _MpgStat({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
          Text(unit, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textDark)),
        ],
      ),
    );
  }
}