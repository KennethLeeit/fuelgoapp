import 'package:flutter/material.dart';
import '../models/models.dart';

class StationBrandBadge extends StatelessWidget {
  final FuelStation station;
  final double size;
  final bool mapMarker;

  const StationBrandBadge({
    super.key,
    required this.station,
    this.size = 52,
    this.mapMarker = false,
  });

  @override
  Widget build(BuildContext context) {
    final identity = _BrandIdentity.from(station);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: mapMarker ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: mapMarker ? null : BorderRadius.circular(13),
        border: Border.all(
            color: mapMarker ? identity.background : const Color(0xFFE5E9F0),
            width: mapMarker ? 4 : 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: identity.logoAsset != null
          ? Padding(
              padding: EdgeInsets.all(mapMarker ? 4 : 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(mapMarker ? size : 9),
                child: Transform.scale(
                  scale: identity.logoScale,
                  alignment: identity.logoAlignment,
                  child: Image.asset(
                    identity.logoAsset!,
                    width: size,
                    height: size,
                    fit: BoxFit.contain,
                    alignment: identity.logoAlignment,
                  ),
                ),
              ),
            )
          : Icon(Icons.local_gas_station_rounded,
              color: identity.background, size: size * 0.48),
    );
  }
}

class _BrandIdentity {
  final Color background;
  final String? logoAsset;
  final double logoScale;
  final Alignment logoAlignment;
  const _BrandIdentity(
    this.background, {
    this.logoAsset,
    this.logoScale = 1,
    this.logoAlignment = Alignment.center,
  });

  factory _BrandIdentity.from(FuelStation station) {
    final raw = station.brand?.trim().isNotEmpty == true
        ? station.brand!
        : station.name;
    final value = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (value.contains('petronas')) {
      return const _BrandIdentity(
        Color(0xFF00A19B),
        logoAsset: 'assets/images/logo_petronas.png',
        logoScale: 1.35,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('shell')) {
      return const _BrandIdentity(
        Color(0xFFFFD500),
        logoAsset: 'assets/images/logo_shell.png',
        logoScale: 1.4,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('petron')) {
      return const _BrandIdentity(
        Color(0xFF003B7A),
        logoAsset: 'assets/images/logo_petron.png',
        logoScale: 1.25,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('caltex') || value.contains('chevron')) {
      return const _BrandIdentity(
        Color(0xFF003B70),
        logoAsset: 'assets/images/logo_caltex.png',
        logoScale: 1.25,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('bhpetrol') || value == 'bhp') {
      return const _BrandIdentity(
        Color(0xFFF58220),
        logoAsset: 'assets/images/logo_bhpetrol.png',
      );
    }
    return _BrandIdentity(station.displayBrandColor);
  }
}

/// A consistent brand-aware visual for stations that do not have a verified
/// branch photo. It deliberately avoids suggesting the generic background is
/// a photo of the exact location.
class StationBrandImage extends StatelessWidget {
  final FuelStation station;
  final bool compact;

  const StationBrandImage({
    super.key,
    required this.station,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final brand = (station.brand?.trim().isNotEmpty == true
            ? station.brand!
            : station.name)
        .trim();
    final imageAsset = _assetForBrand(brand);
    final brandColor = station.displayBrandColor;
    final onBrandColor =
        brandColor.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          imageAsset,
          fit: BoxFit.cover,
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, brandColor.withValues(alpha: 0.8)],
              ),
            ),
          ),
        ),
        if (compact)
          Positioned(
            left: 5,
            right: 5,
            bottom: 5,
            child: Text(
              brand,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w800,
                shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
          )
        else
          Positioned(
            left: 18,
            bottom: 16,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: brandColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Text(
                brand,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onBrandColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _assetForBrand(String brand) {
    final value = brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (value.contains('petronas')) return 'assets/images/station_petronas.png';
    if (value.contains('shell')) return 'assets/images/station_shell.png';
    if (value.contains('petron')) return 'assets/images/station_petron.png';
    if (value.contains('caltex') || value.contains('chevron')) {
      return 'assets/images/station_caltex.png';
    }
    if (value.contains('bhpetrol') || value == 'bhp') {
      return 'assets/images/station_bhpetrol.png';
    }
    return 'assets/images/fuel_station_fallback.png';
  }
}
