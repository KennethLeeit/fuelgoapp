import 'dart:convert';
import 'package:http/http.dart' as http;

/// Live weekly fuel price data published by the Malaysian government
/// (Department of Statistics Malaysia) via the official Open API.
/// Docs: https://developer.data.gov.my/static-api/data-catalogue
/// No API key required.
class FuelPriceService {
  static const String _endpoint = 'https://api.data.gov.my/data-catalogue?id=fuelprice';

  /// Fetches the full fuelprice dataset and returns the latest snapshot:
  /// current RON95 / RON97 / Diesel prices plus their most recent
  /// week-over-week change.
  static Future<FuelPriceSnapshot> fetchLatest() async {
    final uri = Uri.parse(_endpoint);
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw FuelPriceException('Server returned ${response.statusCode}');
    }

    final List<dynamic> rows = json.decode(response.body) as List<dynamic>;
    if (rows.isEmpty) {
      throw FuelPriceException('No fuel price data returned');
    }

    final levels = rows
        .where((r) => r['series_type'] == 'level')
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    final changes = rows
        .where((r) => r['series_type'] == 'change_weekly')
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

    if (levels.isEmpty) {
      throw FuelPriceException('No "level" price rows found in dataset');
    }

    final latestRow = levels.last;
    final latestDate = latestRow['date'] as String;

    Map<String, dynamic>? matchingChange;
    for (final c in changes.reversed) {
      if (c['date'] == latestDate) {
        matchingChange = c;
        break;
      }
    }
    matchingChange ??= changes.isNotEmpty ? changes.last : null;

    double _num(Map<String, dynamic> row, String key) {
      final v = row[key];
      if (v == null) return 0;
      return (v as num).toDouble();
    }

    return FuelPriceSnapshot(
      date: DateTime.parse(latestDate),
      ron95: _num(latestRow, 'ron95'),
      ron97: _num(latestRow, 'ron97'),
      diesel: _num(latestRow, 'diesel'),
      ron95Change: matchingChange != null ? _num(matchingChange, 'ron95') : 0,
      ron97Change: matchingChange != null ? _num(matchingChange, 'ron97') : 0,
      dieselChange: matchingChange != null ? _num(matchingChange, 'diesel') : 0,
    );
  }
}

class FuelPriceSnapshot {
  final DateTime date;
  final double ron95;
  final double ron97;
  final double diesel;
  final double ron95Change;
  final double ron97Change;
  final double dieselChange;

  FuelPriceSnapshot({
    required this.date,
    required this.ron95,
    required this.ron97,
    required this.diesel,
    required this.ron95Change,
    required this.ron97Change,
    required this.dieselChange,
  });

  String get formattedDate {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class FuelPriceException implements Exception {
  final String message;
  FuelPriceException(this.message);
  @override
  String toString() => message;
}