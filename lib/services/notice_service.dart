import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import 'fuel_price_service.dart';

class Notice {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final DateTime date;
  const Notice({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.date,
  });
}

/// Builds the notice feed shown on the Notifications screen (reached via
/// the bell icon on Home) and tracks whether there's anything "unread"
/// for the red dot badge.
///
/// There's no push-notification backend here — notices are generated
/// on-device from data the app already fetches (the weekly government
/// fuel price update), so the feature works without any extra server
/// setup. "Unread" is tracked by comparing the latest price snapshot's
/// date against the last date the user actually opened the Notifications
/// screen (saved locally) — so the badge clears once they've seen it and
/// only reappears when a genuinely new weekly price update lands.
class NoticeService {
  static const _lastSeenKey = 'notices_last_seen_date_v1';

  static List<Notice> fromPriceSnapshot(FuelPriceSnapshot data) {
    final notices = <Notice>[];

    void addIfChanged(String label, double price, double change) {
      if (change == 0) return;
      final up = change > 0;
      notices.add(Notice(
        icon: up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        color: up ? Colors.red : AppColors.evGreen,
        title: '$label ${up ? 'went up' : 'went down'} by RM ${change.abs().toStringAsFixed(2)}',
        subtitle: 'Now RM ${price.toStringAsFixed(2)}/L \u00b7 ${data.formattedDate}',
        date: data.date,
      ));
    }

    addIfChanged('RON95 (Unsubsidised)', data.ron95, data.ron95Change);
    addIfChanged('RON97', data.ron97, data.ron97Change);
    addIfChanged('Diesel', data.diesel, data.dieselChange);

    if (notices.isEmpty) {
      notices.add(Notice(
        icon: Icons.info_outline_rounded,
        color: AppColors.textGrey,
        title: 'Fuel prices unchanged this week',
        subtitle: 'As of ${data.formattedDate}',
        date: data.date,
      ));
    }

    notices.sort((a, b) => b.date.compareTo(a.date));
    return notices;
  }

  /// True if the latest price snapshot is newer than the last time the
  /// user opened the Notifications screen (or they've never opened it) —
  /// drives the red dot badge on Home's bell icon.
  static Future<bool> hasUnseen(FuelPriceSnapshot data) async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeen = prefs.getString(_lastSeenKey);
    if (lastSeen == null) return true;
    final lastSeenDate = DateTime.tryParse(lastSeen);
    if (lastSeenDate == null) return true;
    return data.date.isAfter(lastSeenDate);
  }

  /// Marks the latest snapshot's date as seen, clearing the badge.
  static Future<void> markSeen(FuelPriceSnapshot data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenKey, data.date.toIso8601String());
  }
}
