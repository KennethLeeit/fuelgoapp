import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Simple informational screen describing what FuelGo does, reached from
/// Profile > About. No backend calls — static content only.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _appVersion = '1.0.0';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App logo + name
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(Icons.local_gas_station_rounded,
                          size: 42, color: AppColors.primaryBlue),
                    ),
                    const SizedBox(height: 14),
                    const Text('FuelGo',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Version $_appVersion',
                        style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // What is FuelGo
              _SectionCard(
                title: 'What is FuelGo?',
                icon: Icons.info_outline,
                child: Text(
                  'FuelGo helps you quickly find nearby fuel stations and EV '
                      'charging points wherever you are. Whether you drive a '
                      'petrol/diesel car or an electric vehicle, FuelGo shows '
                      'you the closest options, current prices, and directions '
                      'so you spend less time searching and more time driving.',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark),
                ),
              ),
              const SizedBox(height: 16),

              // What you can do
              _SectionCard(
                title: 'What you can do',
                icon: Icons.checklist_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _FeatureRow(
                      icon: Icons.local_gas_station,
                      iconColor: AppColors.fuelOrange,
                      title: 'Find fuel stations',
                      subtitle: 'Locate nearby petrol/diesel stations and compare prices.',
                    ),
                    SizedBox(height: 12),
                    _FeatureRow(
                      icon: Icons.electric_car,
                      iconColor: AppColors.evGreen,
                      title: 'Find EV chargers',
                      subtitle: 'Discover nearby charging points and check availability.',
                    ),
                    SizedBox(height: 12),
                    _FeatureRow(
                      icon: Icons.tune_rounded,
                      iconColor: AppColors.primaryBlue,
                      title: 'Personalised for your vehicle',
                      subtitle:
                      'Set your vehicle preference in Profile to simplify the app '
                          'to just fuel or just EV, or see both.',
                    ),
                    SizedBox(height: 12),
                    _FeatureRow(
                      icon: Icons.navigation_outlined,
                      iconColor: AppColors.primaryBlue,
                      title: 'Get directions',
                      subtitle: 'Jump straight into navigation to your chosen station.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Mission
              _SectionCard(
                title: 'Our mission',
                icon: Icons.flag_outlined,
                child: Text(
                  'We believe finding fuel or a charge shouldn\'t be a chore. '
                      'FuelGo brings together fuel and EV charging info in one '
                      'simple app, so every driver — no matter what they drive — '
                      'can get back on the road faster.',
                  style: TextStyle(fontSize: 13.5, height: 1.5, color: Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark),
                ),
              ),
              const SizedBox(height: 16),

              // Contact support
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.mail_outline_rounded,
                          size: 18, color: AppColors.primaryBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Contact support',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                          SizedBox(height: 2),
                          Text('fuelgosupport@gmail.com',
                              style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Center(
                child: Text(
                  '© ${DateTime.now().year} FuelGo. All rights reserved.',
                  style: const TextStyle(fontSize: 11, color: AppColors.textGrey),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryBlue),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  const _FeatureRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textGrey, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}