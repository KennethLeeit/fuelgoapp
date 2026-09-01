import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';

/// Resolves whichever of png/jpg/jpeg/webp actually exists in the asset
/// bundle for [baseName] (no extension) — shared by the small brand badge
/// below and by _LocalBrandImage further down, so a logo added as e.g.
/// .jpg shows up without the code needing to know the exact format used.
class _ResolvedLogo extends StatefulWidget {
  final String baseName;
  final double size;
  final double scale;
  final Alignment alignment;
  final Color fallbackColor;
  const _ResolvedLogo({
    required this.baseName,
    required this.size,
    required this.scale,
    required this.alignment,
    required this.fallbackColor,
  });

  @override
  State<_ResolvedLogo> createState() => _ResolvedLogoState();
}

class _ResolvedLogoState extends State<_ResolvedLogo> {
  static final Map<String, String?> _resolvedCache = {};
  static const _extensions = ['png', 'jpg', 'jpeg', 'webp'];
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<String?> _resolve() async {
    if (_resolvedCache.containsKey(widget.baseName)) return _resolvedCache[widget.baseName];
    for (final ext in _extensions) {
      final path = '${widget.baseName}.$ext';
      try {
        await rootBundle.load(path);
        _resolvedCache[widget.baseName] = path;
        return path;
      } catch (_) {
        // Not this extension (or not bundled) — try the next one.
      }
    }
    _resolvedCache[widget.baseName] = null;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || path == null) {
          return Icon(Icons.local_gas_station_rounded, color: widget.fallbackColor, size: widget.size * 0.48);
        }
        return Transform.scale(
          scale: widget.scale,
          alignment: widget.alignment,
          child: Image.asset(
            path,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            alignment: widget.alignment,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.local_gas_station_rounded, color: widget.fallbackColor, size: widget.size * 0.48),
          ),
        );
      },
    );
  }
}

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
      child: identity.logoBaseName != null
          ? Padding(
              padding: EdgeInsets.all(mapMarker ? 4 : 3),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(mapMarker ? size : 9),
                child: _ResolvedLogo(
                  baseName: identity.logoBaseName!,
                  size: size,
                  scale: identity.logoScale,
                  alignment: identity.logoAlignment,
                  fallbackColor: identity.background,
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
  final String? logoBaseName; // asset path WITHOUT extension
  final double logoScale;
  final Alignment logoAlignment;
  const _BrandIdentity(
    this.background, {
    this.logoBaseName,
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
        logoBaseName: 'assets/images/logo_petronas',
        logoScale: 1.35,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('shell')) {
      return const _BrandIdentity(
        Color(0xFFFFD500),
        logoBaseName: 'assets/images/logo_shell',
        logoScale: 1.4,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('petron')) {
      return const _BrandIdentity(
        Color(0xFF003B7A),
        logoBaseName: 'assets/images/logo_petron',
        logoScale: 1.25,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('caltex') || value.contains('chevron')) {
      return const _BrandIdentity(
        Color(0xFF003B70),
        logoBaseName: 'assets/images/logo_caltex',
        logoScale: 1.25,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('bhpetrol') || value == 'bhp') {
      return const _BrandIdentity(
        Color(0xFFF58220),
        logoBaseName: 'assets/images/logo_bhpetrol',
      );
    }
    return _BrandIdentity(station.displayBrandColor);
  }
}

/// A consistent brand-aware visual for stations that do not have a
/// verified branch photo. Resolves, in priority order:
///   1. A real photo, if the station data actually has one
///      (station.imageUrl — e.g. a wikimedia_commons / image tag pulled
///      from OSM by osm_fuel_service.dart).
///   2. A bundled generic brand image, in whichever of png/jpg/jpeg/webp
///      actually exists as assets/images/station_<brand>.*.
///   3. A plain colour card with a fuel-pump icon and the brand name.
/// Step 3 means this can never render blank/broken just because a
/// specific local asset file is missing or misnamed — previously it
/// silently failed to nothing if assets/images/station_<brand>.png in
/// particular wasn't present.
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
    final brandColor = station.displayBrandColor;
    final onBrandColor =
        brandColor.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    final networkUrl = station.imageUrl?.trim();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (networkUrl != null && networkUrl.isNotEmpty)
          Image.network(
            networkUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : Container(color: brandColor.withValues(alpha: 0.15)),
            errorBuilder: (_, __, ___) => _LocalBrandImage(brand: brand, brandColor: brandColor),
          )
        else
          _LocalBrandImage(brand: brand, brandColor: brandColor),
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
}

/// Resolves a bundled generic brand image (assets/images/station_<brand>)
/// in whichever of png/jpg/jpeg/webp actually exists, caching the result
/// per brand for the app's lifetime so the asset bundle is only probed
/// once. Falls back to a plain colour card with a fuel-pump icon if no
/// matching file is found in any supported format.
class _LocalBrandImage extends StatefulWidget {
  final String brand;
  final Color brandColor;
  const _LocalBrandImage({required this.brand, required this.brandColor});

  @override
  State<_LocalBrandImage> createState() => _LocalBrandImageState();
}

class _LocalBrandImageState extends State<_LocalBrandImage> {
  static final Map<String, String?> _resolvedCache = {};
  static const _extensions = ['png', 'jpg', 'jpeg', 'webp'];

  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve(_baseNameFor(widget.brand));
  }

  @override
  void didUpdateWidget(covariant _LocalBrandImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brand != widget.brand) {
      setState(() => _future = _resolve(_baseNameFor(widget.brand)));
    }
  }

  String _baseNameFor(String brand) {
    final value = brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (value.contains('petronas')) return 'assets/images/station_petronas';
    if (value.contains('shell')) return 'assets/images/station_shell';
    if (value.contains('petron')) return 'assets/images/station_petron';
    if (value.contains('caltex') || value.contains('chevron')) {
      return 'assets/images/station_caltex';
    }
    if (value.contains('bhpetrol') || value == 'bhp') {
      return 'assets/images/station_bhpetrol';
    }
    return 'assets/images/fuel_station_fallback';
  }

  Future<String?> _resolve(String baseName) async {
    if (_resolvedCache.containsKey(baseName)) return _resolvedCache[baseName];
    for (final ext in _extensions) {
      final path = '$baseName.$ext';
      try {
        await rootBundle.load(path);
        _resolvedCache[baseName] = path;
        return path;
      } catch (_) {
        // Not this extension (or not bundled) — try the next one.
      }
    }
    _resolvedCache[baseName] = null;
    return null;
  }

  Widget _fallbackCard() => Container(
        color: widget.brandColor.withValues(alpha: 0.85),
        alignment: Alignment.center,
        child: Icon(Icons.local_gas_station_rounded,
            color: Colors.white.withValues(alpha: 0.9), size: 64),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || path == null) {
          return _fallbackCard();
        }
        return Image.asset(
          path,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackCard(),
        );
      },
    );
  }
}
