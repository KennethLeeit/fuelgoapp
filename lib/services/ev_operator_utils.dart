import 'package:flutter/material.dart';

/// Normalises the many raw operator name variants that show up in Open
/// Charge Map / OpenStreetMap data (e.g. "Tesla, Inc.", "Tesla Motors",
/// "TESLA - Supercharger") into a single canonical network name, so the
/// same badge/colour/filter is used no matter which source or exact
/// string the charger came from. Mirrors the brand-normalisation pattern
/// already used for fuel stations (`_normaliseBrand` in
/// mygeomap_fuel_service.dart).
String? normaliseEvOperator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (compact.contains('tesla')) return 'Tesla';
  if (compact.contains('gentari')) return 'Gentari';
  if (compact.contains('chargev')) return 'ChargEV';
  if (compact.contains('jomcharge')) return 'JomCharge';
  if (compact.contains('dchub')) return 'DC HUB';
  if (compact.contains('shellrecharge') || compact.contains('shellev') || compact == 'shell') {
    return 'Shell Recharge';
  }
  if (compact.contains('chargesini')) return 'ChargeSini';
  if (compact.contains('evduty')) return 'EVduty';
  // Gentari is Petronas' dedicated clean-energy / EV charging arm, so
  // stray "Petronas"-tagged EV points are folded into the same network.
  if (compact.contains('petronas')) return 'Gentari';
  if (compact.contains('bmw')) return 'BMW Charging';
  if (compact.contains('porsche')) return 'Porsche Charging';
  if (compact.contains('yinson')) return 'Yinson GreenTech';
  return value.trim();
}

/// Rough speed tier for a charger's max power output, used to colour-code
/// the power badge so a 7kW AC point and a 350kW DC rapid charger don't
/// look the same at a glance.
enum ChargeSpeedTier { slowAc, fastAc, rapidDc, unknown }

ChargeSpeedTier chargeSpeedTierFor(int? maxPowerKw) {
  if (maxPowerKw == null || maxPowerKw <= 0) return ChargeSpeedTier.unknown;
  if (maxPowerKw < 22) return ChargeSpeedTier.slowAc;
  if (maxPowerKw <= 50) return ChargeSpeedTier.fastAc;
  return ChargeSpeedTier.rapidDc;
}

Color colorForSpeedTier(ChargeSpeedTier tier) {
  switch (tier) {
    case ChargeSpeedTier.slowAc:
      return const Color(0xFF2F6FED); // AC slow — blue
    case ChargeSpeedTier.fastAc:
      return const Color(0xFFFF9800); // AC fast — orange
    case ChargeSpeedTier.rapidDc:
      return const Color(0xFFE53935); // DC rapid — red
    case ChargeSpeedTier.unknown:
      return const Color(0xFF8A8F98); // grey
  }
}

String labelForSpeedTier(ChargeSpeedTier tier) {
  switch (tier) {
    case ChargeSpeedTier.slowAc:
      return 'AC \u00b7 Slow';
    case ChargeSpeedTier.fastAc:
      return 'AC \u00b7 Fast';
    case ChargeSpeedTier.rapidDc:
      return 'DC \u00b7 Rapid';
    case ChargeSpeedTier.unknown:
      return 'Power unknown';
  }
}

/// A best-effort icon for a connector type string (e.g. "CCS2", "Type 2",
/// "CHAdeMO", "Tesla Supercharger"). Flutter's Material icon set has no
/// literal connector-shape icons, so this picks visually distinct
/// stand-ins rather than using the same icon for every connector.
IconData iconForConnector(String connector) {
  final value = connector.toLowerCase();
  if (value.contains('chademo')) return Icons.flash_on_rounded;
  if (value.contains('ccs')) return Icons.ev_station_rounded;
  if (value.contains('tesla')) return Icons.bolt_rounded;
  if (value.contains('type 2') || value.contains('type 1')) return Icons.power_rounded;
  if (value.contains('schuko')) return Icons.electrical_services_rounded;
  return Icons.electrical_services_rounded;
}
