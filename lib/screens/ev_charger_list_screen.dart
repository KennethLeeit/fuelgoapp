import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/osm_ev_charger_service.dart';
import 'ev_charger_detail_screen.dart';

class EVChargerListScreen extends StatefulWidget {
  const EVChargerListScreen({super.key});
  @override
  State<EVChargerListScreen> createState() => _EVChargerListScreenState();
}

class _EVChargerListScreenState extends State<EVChargerListScreen> {
  String _query = '';
  late Future<List<EVCharger>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }


  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
        title: const Text('EV Charger', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search EV charger...', prefixIcon: Icon(Icons.search)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textDark,
                    side: const BorderSide(color: AppColors.cardBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Spacer(),
                const Text('Live data (OpenStreetMap)', style: TextStyle(color: AppColors.textGrey, fontSize: 11)),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EVCharger>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _ErrorState(onRetry: _retry);
                }
                final chargers = snapshot.data!
                    .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
                    .toList();
                if (chargers.isEmpty) {
                  return const Center(child: Text('No EV chargers found nearby', style: TextStyle(color: AppColors.textGrey)));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;
  const _ErrorState({required this.onRetry, this.message});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.textGrey),
            const SizedBox(height: 12),
            Text(
              message ?? 'Could not load nearby EV chargers.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textGrey),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
