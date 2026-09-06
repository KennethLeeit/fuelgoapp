import 'package:flutter/material.dart';

String? normaliseEvOperator(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final compact = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (compact.contains('tesla')) return 'Tesla';
  if (compact.contains('gentari')) return 'Gentari';
  if (compact.contains('chargev')) return 'ChargEV';
  if (compact.contains('jomcharge')) return 'JomCharge';
  if (compact.contains('dchub')) return 'DC HUB';
  if (compact.contains('shellrecharge') ||
      compact.contains('shellev') ||
      compact == 'shell') {
    return 'Shell Recharge';
  }
  if (compact.contains('chargesini')) return 'ChargeSini';
  if (compact.contains('evduty')) return 'EVduty';

  if (compact.contains('petronas')) return 'Gentari';
  if (compact.contains('bmw')) return 'BMW Charging';
  if (compact.contains('porsche')) return 'Porsche Charging';
  if (compact.contains('yinson')) return 'Yinson GreenTech';
  return value.trim();
}

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
      return const Color(0xFF2F6FED);
    case ChargeSpeedTier.fastAc:
      return const Color(0xFFFF9800);
    case ChargeSpeedTier.rapidDc:
      return const Color(0xFFE53935);
    case ChargeSpeedTier.unknown:
      return const Color(0xFF8A8F98);
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

IconData iconForConnector(String connector) {
  final value = connector.toLowerCase();
  if (value.contains('chademo')) return Icons.flash_on_rounded;
  if (value.contains('ccs')) return Icons.ev_station_rounded;
  if (value.contains('tesla')) return Icons.bolt_rounded;
  if (value.contains('type 2') || value.contains('type 1'))
    return Icons.power_rounded;
  if (value.contains('schuko')) return Icons.electrical_services_rounded;
  return Icons.electrical_services_rounded;
}
