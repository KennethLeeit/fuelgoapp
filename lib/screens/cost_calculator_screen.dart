import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/vehicle_preference_service.dart';
import '../services/fuel_price_service.dart';
import '../services/reference_prices.dart';

class CostCalculatorScreen extends StatefulWidget {
  const CostCalculatorScreen({super.key});
  @override
  State<CostCalculatorScreen> createState() => _CostCalculatorScreenState();
}

class _CostCalculatorScreenState extends State<CostCalculatorScreen> {
  bool _isFuel = true;
  final _distanceController = TextEditingController(text: '120');
  final _efficiencyController = TextEditingController(text: '15.0');
  String _fuelType = 'RON95 (Unsubsidised)';
  String _evProvider = 'ChargeEV';

  late Future<FuelPriceSnapshot> _priceFuture;

  @override
  void initState() {
    super.initState();
    _priceFuture = FuelPriceService.fetchLatest();
  }

  void _retry() => setState(() => _priceFuture = FuelPriceService.fetchLatest());

  // Built from the same live snapshot Home shows, plus the fixed
  // subsidised rate — so the calculator always follows current fuel
  // prices instead of a separate hardcoded copy that could drift.
  Map<String, double> _fuelPrices(FuelPriceSnapshot data) => {
        'RON95 (Subsidised)': ReferencePrices.ron95Subsidised,
        'RON95 (Unsubsidised)': data.ron95,
        'RON97': data.ron97,
        'Diesel': data.diesel,
      };

  double get _distance => double.tryParse(_distanceController.text) ?? 0;
  double get _efficiency => double.tryParse(_efficiencyController.text) ?? 1;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FuelPriceSnapshot>(
      future: _priceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
              title: const Text('Cost Calculator', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
              title: const Text('Cost Calculator', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, color: AppColors.textGrey, size: 32),
                  const SizedBox(height: 8),
                  const Text('Could not load current fuel prices', style: TextStyle(color: AppColors.textGrey)),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final fuelPrices = _fuelPrices(snapshot.data!);

        return AnimatedBuilder(
          animation: VehiclePreferenceService.instance,
          builder: (context, _) {
            final vp = VehiclePreferenceService.instance;
            final locked = vp.isLocked;
            // When locked to one vehicle type, force the calculator into that
            // mode regardless of the local toggle state.
            final isFuel = locked ? vp.showFuel : _isFuel;

            final price = isFuel
                ? (fuelPrices[_fuelType] ?? 0)
                : (ReferencePrices.evProviderRates[_evProvider] ?? 0);
            final needed = isFuel ? (_efficiency == 0 ? 0 : _distance / _efficiency) : (_distance * 0.2);
            final cost = needed * price;

            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
                title: const Text('Cost Calculator', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!locked) ...[
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Expanded(child: _toggleButton('Fuel', isFuel, () => setState(() => _isFuel = true))),
                            Expanded(child: _toggleButton('EV', !isFuel, () => setState(() => _isFuel = false))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      children: [
                        Icon(isFuel ? Icons.local_gas_station : Icons.electric_car,
                            color: isFuel ? AppColors.fuelOrange : AppColors.evGreen),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isFuel ? 'Fuel Vehicle' : 'Electric Vehicle', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(
                              isFuel ? 'Estimate your fuel cost for the trip' : 'Estimate your charging cost for the trip',
                              style: const TextStyle(fontSize: 12, color: AppColors.textGrey),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('INPUT DETAILS', style: TextStyle(fontSize: 12, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _inputCard(
                      icon: Icons.location_on_outlined,
                      label: 'Distance',
                      sub: 'Total trip distance',
                      child: SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _distanceController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              suffixText: 'km', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 10)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _inputCard(
                      icon: Icons.speed_outlined,
                      label: isFuel ? 'Fuel Efficiency' : 'Energy Efficiency',
                      sub: 'Average mileage',
                      child: SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _efficiencyController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                              suffixText: isFuel ? 'km/L' : 'km/kWh',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _inputCard(
                      icon: Icons.local_gas_station_outlined,
                      label: isFuel ? 'Fuel Type' : 'Charging Provider',
                      sub: isFuel ? 'Select fuel type' : 'Select charging provider',
                      child: DropdownButton<String>(
                        value: isFuel ? _fuelType : _evProvider,
                        underline: const SizedBox(),
                        items: (isFuel ? fuelPrices.keys : ReferencePrices.evProviderRates.keys)
                            .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          if (isFuel) {
                            _fuelType = v!;
                          } else {
                            _evProvider = v!;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(isFuel ? 'CURRENT FUEL PRICE' : 'CURRENT CHARGING PRICE',
                        style: const TextStyle(fontSize: 12, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.evGreen.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(isFuel ? Icons.local_gas_station : Icons.bolt, color: AppColors.evGreen),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(isFuel ? _fuelType : _evProvider, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(
                                  isFuel && _fuelType == 'RON95 (Subsidised)'
                                      ? 'Fixed government rate'
                                      : 'Current price in your area',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                                ),
                              ],
                            ),
                          ),
                          Text('RM ${price.toStringAsFixed(2)} ${isFuel ? '/L' : '/kWh'}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('ESTIMATED COST', style: TextStyle(fontSize: 12, color: AppColors.textGrey, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: const Color(0xFFEAF1FD), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          const CircleAvatar(radius: 22, backgroundColor: AppColors.primaryBlue, child: Icon(Icons.calculate, color: Colors.white)),
                          const SizedBox(height: 12),
                          Text(isFuel ? 'Estimated Fuel Needed' : 'Estimated Energy Needed', style: const TextStyle(color: AppColors.textGrey)),
                          const SizedBox(height: 4),
                          Text('${needed.toStringAsFixed(2)} ${isFuel ? 'L' : 'kWh'}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                          const SizedBox(height: 16),
                          const Text('Estimated Cost', style: TextStyle(color: AppColors.textGrey)),
                          const SizedBox(height: 4),
                          Text('RM ${cost.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFF1F3F6), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: AppColors.textGrey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isFuel
                                  ? 'How it\'s calculated:\nDistance ÷ Fuel efficiency = Fuel needed\nFuel needed × Fuel price = Estimated cost'
                                  : 'How it\'s calculated:\nDistance × Energy usage = Energy needed\nEnergy needed × Price = Estimated cost',
                              style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Note: These are estimated values.\nActual cost may vary.',
                        style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _toggleButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textGrey, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _inputCard({required IconData icon, required String label, required String sub, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.cardBorder)),
      child: Row(
        children: [
          CircleAvatar(radius: 18, backgroundColor: const Color(0xFFF1F3F6), child: Icon(icon, size: 18, color: AppColors.textDark)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

