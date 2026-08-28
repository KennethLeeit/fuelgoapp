/// Prices that aren't part of the live data.gov.my fuel feed but still need
/// to appear consistently on both the Home screen and the Cost Calculator.
/// Centralised here so the two screens can't drift out of sync with each
/// other — update a rate once, both screens follow.
class ReferencePrices {
  /// RON95 (Subsidised) is capped by the Malaysian government under the
  /// targeted fuel subsidy scheme, not published on the live price feed —
  /// so it's tracked as a constant rather than fetched. Update this if the
  /// government revises the subsidised ceiling.
  static const double ron95Subsidised = 1.99;

  /// Indicative "from" EV charging rates by operator (RM/kWh). Real rates
  /// vary by location and charger power tier — these are shown as a
  /// starting-from indication on Home and used as the Cost Calculator's
  /// default per-provider rate.
  static const Map<String, double> evProviderRates = {
    'ChargeEV': 1.20,
    'Gentari': 1.60,
    'JomCharge': 1.10,
  };
}
