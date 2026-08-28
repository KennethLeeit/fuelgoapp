import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/vehicle_preference_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'about_screen.dart';
import 'setting_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Icon(Icons.notifications_none_rounded, size: 26),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFFEFF3F8),
                    backgroundImage: AuthService.currentUser?.photoURL?.trim().isNotEmpty == true
                        ? NetworkImage(AuthService.currentUser!.photoURL!)
                        : null,
                    child: AuthService.currentUser?.photoURL?.trim().isNotEmpty != true
                        ? const Icon(Icons.person, size: 34, color: AppColors.primaryBlue)
                        : null,
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
                                  AuthService.updateVehiclePreference(drivesFuel: vp.drivesFuel, drivesEV: vp.drivesEV);
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
                                  AuthService.updateVehiclePreference(drivesFuel: vp.drivesFuel, drivesEV: vp.drivesEV);
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
