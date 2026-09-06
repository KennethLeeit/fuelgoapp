import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  static const String _supportEmail = 'fuelgosupport@gmail.com';

  static const List<_Faq> _faqs = [
    _Faq(
      question: 'Why do some stations show "no fuel details available"?',
      answer:
          'Fuel station data comes from Malaysia\'s government MyGeoMap service and '
          'OpenStreetMap. Neither always has complete fuel-type or facility '
          'information for every station — this is a data-source gap, not something '
          'wrong with your account. We show typical availability where possible '
          'and label it as unconfirmed rather than guessing silently.',
    ),
    _Faq(
      question: 'Why does the app need my location?',
      answer:
          'Location is used to find fuel stations and EV chargers near you and to '
          'calculate accurate distances. It\'s only used on-device and to query '
          'nearby-places APIs — it isn\'t sold or shared for advertising.',
    ),
    _Faq(
      question: 'How do I switch between Fuel and EV mode?',
      answer:
          'Go to Profile > Vehicle Preference. Selecting only one vehicle type '
          'simplifies the whole app to just that feature set (Home, Cost '
          'Calculator, and the Map). Selecting both — or neither — shows '
          'everything.',
    ),
    _Faq(
      question: 'My favourites disappeared after logging in on another device.',
      answer: 'Favourites are synced to your account, but the list you see is '
          'refreshed against nearby-places data each time — a favourite outside '
          'your current search area may not show up until you\'re near it again. '
          'It\'s still saved on your account either way.',
    ),
    _Faq(
      question: 'How do I change my password or email?',
      answer:
          'Go to Profile > Settings. You\'ll need to confirm your current password '
          'to change it, for security. To reset a forgotten password, use "Forgot '
          'Password?" on the Login screen instead.',
    ),
    _Faq(
      question: 'How do I delete my account?',
      answer:
          'Contact us at $_supportEmail with the email address on your account '
          'and we\'ll remove your data.',
    ),
  ];

  Future<void> _emailSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('FuelGo Support Request')}',
    );
    await launchUrl(uri);
  }

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
        title: const Text('Help & Support',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
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
                      Icon(Icons.support_agent_rounded,
                          size: 18, color: AppColors.primaryBlue),
                      const SizedBox(width: 8),
                      const Text('Need help?',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Check the frequently asked questions below, or reach out directly and we\'ll get back to you.',
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textGrey, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _emailSupport,
                      icon: const Icon(Icons.mail_outline_rounded, size: 18),
                      label: const Text('Email Support'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(_supportEmail,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textGrey)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Frequently Asked Questions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            ..._faqs.map((faq) => _FaqTile(faq: faq)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Faq {
  final String question;
  final String answer;
  const _Faq({required this.question, required this.answer});
}

class _FaqTile extends StatelessWidget {
  final _Faq faq;
  const _FaqTile({required this.faq});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            faq.question,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          children: [
            Text(
              faq.answer,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textGrey, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
