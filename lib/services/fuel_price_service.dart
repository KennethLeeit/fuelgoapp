import 'dart:convert';
import 'package:http/http.dart' as http;

class FuelPriceService {
  static const String _endpoint =
      'https://api.data.gov.my/data-catalogue?id=fuelprice';

  static Future<FuelPriceSnapshot> fetchLatest() async {
    final uri = Uri.parse(_endpoint);
    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw FuelPriceException('Server returned ${response.statusCode}');
    }

    final List<dynamic> rows = json.decode(response.body) as List<dynamic>;
    return parseRows(rows);
  }

  static FuelPriceSnapshot parseRows(List<dynamic> rows) {
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
    double number(Map<String, dynamic> row, String key) {
      final v = row[key];
      if (v == null) return 0;
      return (v as num).toDouble();
    }

    return FuelPriceSnapshot(
      date: DateTime.parse(latestDate),
      previousDate: levels.length > 1
          ? DateTime.tryParse(levels[levels.length - 2]['date'].toString())
          : null,
      ron95: number(latestRow, 'ron95'),
      ron97: number(latestRow, 'ron97'),
      diesel: number(latestRow, 'diesel'),
      dieselEastMalaysia: number(latestRow, 'diesel_eastmsia'),
      previousRon95:
          levels.length > 1 ? number(levels[levels.length - 2], 'ron95') : null,
      previousRon97:
          levels.length > 1 ? number(levels[levels.length - 2], 'ron97') : null,
      previousDiesel: levels.length > 1
          ? number(levels[levels.length - 2], 'diesel')
          : null,
      previousDieselEastMalaysia: levels.length > 1
          ? number(levels[levels.length - 2], 'diesel_eastmsia')
          : null,
      ron95Change: matchingChange != null ? number(matchingChange, 'ron95') : 0,
      ron97Change: matchingChange != null ? number(matchingChange, 'ron97') : 0,
      dieselChange:
          matchingChange != null ? number(matchingChange, 'diesel') : 0,
    );
  }
}

class FuelPriceSnapshot {
  final DateTime date;
  final DateTime? previousDate;
  final double ron95;
  final double ron97;
  final double diesel;
  final double dieselEastMalaysia;
  final double? previousRon95;
  final double? previousRon97;
  final double? previousDiesel;
  final double? previousDieselEastMalaysia;
  final double ron95Change;
  final double ron97Change;
  final double dieselChange;

  FuelPriceSnapshot({
    required this.date,
    this.previousDate,
    required this.ron95,
    required this.ron97,
    required this.diesel,
    this.dieselEastMalaysia = 0,
    this.previousRon95,
    this.previousRon97,
    this.previousDiesel,
    this.previousDieselEastMalaysia,
    required this.ron95Change,
    required this.ron97Change,
    required this.dieselChange,
  });

  String get formattedDate {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
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
