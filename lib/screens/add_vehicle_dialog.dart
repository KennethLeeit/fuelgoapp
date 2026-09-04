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

  // --- Manual entry mode (for vehicles the EPA lookup can't find, e.g.
  // non-US market cars) ---
  bool _manualMode = false;
  final _manualFormKey = GlobalKey<FormState>();
  final _manualYearController = TextEditingController();
  final _manualBrandController = TextEditingController();
  final _manualModelController = TextEditingController();
  final _manualAvgKmLController = TextEditingController();
  static const _fuelTypeOptions = [
    'RON95 (Standard)',
    'RON97 (Premium)',
    'Diesel',
    'Electric',
  ];
  String? _manualFuelType;
  bool _manualSaving = false;
  String? _manualError;

  void _enterManualMode() {
    setState(() {
      _manualMode = true;
      _manualError = null;
    });
  }

  void _exitManualMode() {
    setState(() {
      _manualMode = false;
      _manualError = null;
    });
  }

  Future<void> _saveManualAndClose() async {
    if (_manualSaving) return;
    final form = _manualFormKey.currentState;
    if (form == null || !form.validate()) return;
    setState(() {
      _manualSaving = true;
      _manualError = null;
    });
    try {
      await VehicleRepository.addManualVehicle(
        make: _manualBrandController.text.trim(),
        model: _manualModelController.text.trim(),
        avgKmL: _manualFuelType == 'Electric'
            ? null
            : double.parse(_manualAvgKmLController.text.trim()),
        combinedKwhPer100Km: _manualFuelType == 'Electric'
            ? double.parse(_manualAvgKmLController.text.trim())
            : null,
        fuelType: _manualFuelType!,
        year: _manualYearController.text.trim().isEmpty
            ? null
            : int.tryParse(_manualYearController.text.trim()),
      );
      if (mounted) Navigator.of(context).pop();
    } on VehicleRepositoryException catch (e) {
      setState(() => _manualError = e.message);
    } catch (_) {
      setState(
              () => _manualError = 'Could not save the vehicle. Please try again.');
    } finally {
      if (mounted) setState(() => _manualSaving = false);
    }
  }

  @override
  void dispose() {
    _manualYearController.dispose();
    _manualBrandController.dispose();
    _manualModelController.dispose();
    _manualAvgKmLController.dispose();
    super.dispose();
  }

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
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
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
                  Expanded(
                    child: Text(
                        _manualMode ? 'Enter Vehicle Manually' : 'Add Vehicle',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close,
                        size: 20, color: AppColors.textGrey),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _manualMode
                    ? 'Can\'t find your car in the lookup? Enter its details yourself.'
                    : 'Enter your car\'s year, brand and model to look up its EPA fuel efficiency.',
                style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: _manualMode ? _buildManualForm() : _buildLookupForm(),
                ),
              ),
              const SizedBox(height: 16),
              _manualMode ? _buildManualButtonRow() : _buildLookupButtonRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLookupForm() {
    return Column(
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
          _ErrorBanner(message: _error!),
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
    );
  }

  Widget _buildLookupButtonRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _enterManualMode,
            child: const Text('Enter Manually'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: (_result == null || _saving) ? null : _saveAndClose,
            child: _saving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: Colors.white),
            )
                : const Text('Add Vehicle'),
          ),
        ),
      ],
    );
  }

  Widget _buildManualForm() {
    return Form(
      key: _manualFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ManualField(
            label: 'Brand',
            hint: 'e.g. Proton, Perodua, Toyota',
            controller: _manualBrandController,
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Enter the brand' : null,
          ),
          const SizedBox(height: 12),
          _ManualField(
            label: 'Model / Name',
            hint: 'e.g. Saga, Myvi, Vios',
            controller: _manualModelController,
            validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Enter the model' : null,
          ),
          const SizedBox(height: 12),
          _ManualField(
            label: 'Year (optional)',
            hint: 'e.g. 2020',
            controller: _manualYearController,
            keyboardType: TextInputType.number,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              return int.tryParse(v.trim()) == null
                  ? 'Enter a valid year'
                  : null;
            },
          ),
          const SizedBox(height: 12),
          _ManualField(
            label: _manualFuelType == 'Electric'
                ? 'Energy use (kWh / 100 km)'
                : 'Average fuel efficiency (km/L)',
            hint: _manualFuelType == 'Electric' ? 'e.g. 15.5' : 'e.g. 14.5',
            controller: _manualAvgKmLController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return _manualFuelType == 'Electric'
                    ? 'Enter the energy use'
                    : 'Enter the average km/L';
              }
              final parsed = double.tryParse(v.trim());
              if (parsed == null || parsed <= 0) return 'Enter a valid number';
              return null;
            },
          ),
          const SizedBox(height: 12),
          Text('Fuel Type',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)),
          const SizedBox(height: 6),
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _manualFuelType,
                hint: const Text('Select fuel type',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                items: _fuelTypeOptions
                    .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(f, style: const TextStyle(fontSize: 14))))
                    .toList(),
                onChanged: (v) => setState(() => _manualFuelType = v),
              ),
            ),
          ),
          if (_manualFuelType == null) ...[
            const SizedBox(height: 4),
            const Text('Required',
                style: TextStyle(color: Colors.red, fontSize: 11)),
          ],
          if (_manualError != null) ...[
            const SizedBox(height: 14),
            _ErrorBanner(message: _manualError!),
          ],
        ],
      ),
    );
  }

  Widget _buildManualButtonRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _manualSaving ? null : _exitManualMode,
            child: const Text('Back'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: (_manualFuelType == null || _manualSaving)
                ? null
                : _saveManualAndClose,
            child: _manualSaving
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2.2, color: Colors.white),
            )
                : const Text('Save Vehicle'),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodyLarge?.color ??
                          AppColors.textDark))),
        ],
      ),
    );
  }
}

class _ManualField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _ManualField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textGrey, fontSize: 13),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      ],
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
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)),
        const SizedBox(height: 6),
        Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled
                ? Theme.of(context).cardColor
                : Theme.of(context).disabledColor.withValues(alpha: .06),
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
              Text('Loading…',
                  style: TextStyle(color: AppColors.textGrey)),
            ],
          )
              : DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              isExpanded: true,
              value: value,
              hint: Text(
                enabled ? 'Select $label' : 'Select $label above first',
                style: const TextStyle(
                    color: AppColors.textGrey, fontSize: 13),
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
        color: AppColors.primaryBlue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: .18)),
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
                  label: 'Highway', value: _kmL(result.highwayMpg), unit: unit),
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
  const _MpgStat(
      {required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value.toStringAsFixed(1),
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue)),
          Text(unit,
              style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark)),
        ],
      ),
    );
  }
}