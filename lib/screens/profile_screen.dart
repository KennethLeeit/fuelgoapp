import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/vehicle_preference_service.dart';
import '../services/favourites_service.dart';
import '../services/auth_service.dart';
import '../services/vehicle_repository.dart';
import 'login_screen.dart';
import 'about_screen.dart';
import 'setting_screen.dart';
import 'add_vehicle_dialog.dart';

/// Reads [key] from [data] and coerces it to a double, whether it was
/// stored as a Firestore number or as a string.
double _doubleFromDynamic(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// Reads [key] from [data] and coerces it to an int, whether it was stored
/// as a Firestore number or as a string (e.g. "2020").
int _intFromDynamic(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Picks the fuel-pump icon colour based on the vehicle's fuel type:
/// standard petrol keeps the existing orange, premium petrol is green,
/// diesel is black. Electric vehicles are handled separately by the caller.
Color _fuelIconColor(String fuelType) {
  final f = fuelType.toLowerCase();
  if (f.contains('diesel')) return Colors.black;
  if (f.contains('premium')) return Colors.green;
  return AppColors.fuelOrange;
}

/// A vehicle document as read back from Firestore, ready for display in
/// "My Vehicles". Efficiency fields are stored (and shown) in km/L.
class _SavedVehicle {
  final String docId;
  final int year;
  final String make;
  final String model;
  final String fuelType;
  final double cityKmL;
  final double highwayKmL;
  final double combinedKmL;
  final bool isElectric;
  final bool isFavourite;

  _SavedVehicle.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc)
      : docId = doc.id,
        year = _intFromDynamic(doc.data(), 'year'),
        make = doc.data()['make'] as String? ?? '',
        model = doc.data()['model'] as String? ?? '',
        fuelType = doc.data()['fuelType'] as String? ?? '',
        cityKmL = _doubleFromDynamic(doc.data(), 'cityKmL'),
        highwayKmL = _doubleFromDynamic(doc.data(), 'highwayKmL'),
        combinedKmL = _doubleFromDynamic(doc.data(), 'combinedKmL'),
        isElectric = doc.data()['isElectric'] as bool? ?? false,
        isFavourite = doc.data()['isFavourite'] as bool? ?? false;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _saveVehiclePreference(VehiclePreferenceService vp) async {
    final error = await AuthService.updateVehiclePreference(drivesFuel: vp.drivesFuel, drivesEV: vp.drivesEV);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _onAddVehicleTap() async {
    // AddVehicleDialog already persists the vehicle to Firestore via
    // VehicleRepository.addVehicle before it pops. The watchMyVehicles()
    // stream below picks up the new document automatically, so there's
    // nothing to do with the returned value here.
    await showAddVehicleDialog(context);
  }

  Future<void> _removeVehicle(String docId) async {
    try {
      await VehicleRepository.deleteVehicle(docId);
    } on VehicleRepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _toggleFavourite(_SavedVehicle vehicle) async {
    try {
      await VehicleRepository.setFavourite(vehicle.docId, !vehicle.isFavourite);
    } on VehicleRepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: Color(0xFFEFF3F8),
                    child: Icon(Icons.person, size: 34, color: AppColors.primaryBlue),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AuthService.currentUser?.displayName?.isNotEmpty == true
                            ? AuthService.currentUser!.displayName!
                            : 'FuelGo User',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(AuthService.currentUser?.email ?? '', style: const TextStyle(color: AppColors.textGrey)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.directions_car_filled_outlined, color: AppColors.textDark),
                        SizedBox(width: 10),
                        Text('Vehicle Preference', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 32, top: 2),
                      child: Text('Help us customise your experience',
                          style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEFF3FB), borderRadius: BorderRadius.circular(10)),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, size: 18, color: AppColors.primaryBlue),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                'Select only one to simplify the app to just that feature set, or select both to see everything.',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Please select the type of vehicle you drive.',
                        style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    const SizedBox(height: 12),
                    AnimatedBuilder(
                      animation: VehiclePreferenceService.instance,
                      builder: (context, _) {
                        final vp = VehiclePreferenceService.instance;
                        return Row(
                          children: [
                            Expanded(
                              child: _VehicleOption(
                                icon: Icons.electric_car,
                                label: 'I drive an\nEV (Electric Vehicle)',
                                selected: vp.drivesEV,
                                color: AppColors.evGreen,
                                onTap: () {
                                  vp.setDrivesEV(!vp.drivesEV);
                                  _saveVehiclePreference(vp);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _VehicleOption(
                                icon: Icons.local_gas_station,
                                label: 'I drive a\nFuel Car',
                                selected: vp.drivesFuel,
                                color: AppColors.fuelOrange,
                                onTap: () {
                                  vp.setDrivesFuel(!vp.drivesFuel);
                                  _saveVehiclePreference(vp);
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    AnimatedBuilder(
                      animation: VehiclePreferenceService.instance,
                      builder: (context, _) {
                        final vp = VehiclePreferenceService.instance;
                        if (!vp.isLocked) return const SizedBox.shrink();
                        final label = vp.mode == VehicleMode.fuelOnly
                            ? 'Showing fuel station features only across the app.'
                            : 'Showing EV charger features only across the app.';
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 14, color: AppColors.evGreen),
                              const SizedBox(width: 6),
                              Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textGrey))),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_gas_station_outlined, color: AppColors.textDark),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('My Vehicles', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        TextButton.icon(
                          onPressed: _onAddVehicleTap,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Vehicle'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryBlue,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: VehicleRepository.watchMyVehicles(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 16, bottom: 8),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          // ignore: avoid_print
                          print('watchMyVehicles error: ${snapshot.error}');
                          return Padding(
                            padding: const EdgeInsets.only(left: 32, top: 2, bottom: 4),
                            child: Text(
                              'Could not load your vehicles: ${snapshot.error}',
                              style: const TextStyle(color: AppColors.textGrey, fontSize: 12),
                            ),
                          );
                        }
                        final docs = snapshot.data?.docs ?? [];
                        if (docs.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(left: 32, top: 2, bottom: 4),
                            child: Text(
                              'Add a car to see its EPA fuel efficiency here.',
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12),
                            ),
                          );
                        }
                        final vehicles = docs.map(_SavedVehicle.fromDoc).toList();
                        return Column(
                          children: [
                            const SizedBox(height: 4),
                            ...vehicles.map((vehicle) {
                              final unit = vehicle.isElectric ? 'km/L (eq)' : 'km/L';
                              return Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF3FB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      vehicle.isElectric ? Icons.electric_car : Icons.local_gas_station,
                                      color: vehicle.isElectric
                                          ? AppColors.evGreen
                                          : _fuelIconColor(vehicle.fuelType),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            vehicle.year > 0
                                                ? '${vehicle.year} ${vehicle.make} ${vehicle.model}'
                                                : '${vehicle.make} ${vehicle.model}',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'City ${vehicle.cityKmL.toStringAsFixed(1)} • Hwy ${vehicle.highwayKmL.toStringAsFixed(1)} • Combined ${vehicle.combinedKmL.toStringAsFixed(1)} $unit',
                                            style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        vehicle.isFavourite ? Icons.star : Icons.star_border,
                                        size: 20,
                                        color: vehicle.isFavourite ? Colors.amber : AppColors.textGrey,
                                      ),
                                      tooltip: vehicle.isFavourite ? 'Remove favourite' : 'Mark as favourite',
                                      onPressed: () => _toggleFavourite(vehicle),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                      tooltip: 'Delete vehicle',
                                      onPressed: () => _removeVehicle(vehicle.docId),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _ProfileTile(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  if (context.mounted) setState(() {});
                },
              ),
              _ProfileTile(icon: Icons.help_outline, label: 'Help & Support', onTap: () {}),
              _ProfileTile(
                icon: Icons.info_outline,
                label: 'About',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder)),
                child: ListTile(
                  leading: const Icon(Icons.power_settings_new_rounded, color: Colors.red),
                  title: const Text('Logout',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    await AuthService.signOut();
                    // Clear locally-cached account data so it doesn't
                    // briefly show up if a different account signs in on
                    // this device next.
                    VehiclePreferenceService.instance.reset();
                    FavouritesService.instance.reset();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _VehicleOption(
      {required this.icon,
        required this.label,
        required this.selected,
        required this.color,
        required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : AppColors.cardBorder, width: selected ? 1.5 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? color : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? color : AppColors.textGrey),
              ),
              child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ProfileTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorder)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.textDark),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textGrey),
        onTap: onTap,
      ),
    );
  }
}