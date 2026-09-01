import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/models.dart';
import '../services/ev_operator_utils.dart';

/// EV-charger equivalent of StationBrandBadge (see station_brand_image.dart):
/// shows the charging network's real logo when the operator is recognised,
/// and falls back to the previous colour-coded bolt icon otherwise — so an
/// unrecognised or unbranded charger never shows a broken image.
class EVChargerBrandBadge extends StatelessWidget {
  final EVCharger charger;
  final double size;
  final bool mapMarker;

  const EVChargerBrandBadge({
    super.key,
    required this.charger,
    this.size = 52,
    this.mapMarker = false,
  });

  @override
  Widget build(BuildContext context) {
    final identity = _EvBrandIdentity.from(charger);
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
                child: _EvLogoImage(
                  baseName: identity.logoBaseName!,
                  size: size,
                  scale: identity.logoScale,
                  alignment: identity.logoAlignment,
                  fallbackColor: identity.background,
                ),
              ),
            )
          : Icon(Icons.ev_station_rounded, color: identity.background, size: size * 0.48),
    );
  }
}

/// Logo files may have been added as .png, .jpg, .jpeg, or .webp — this
/// widget resolves whichever extension actually exists in the asset
/// bundle for [baseName] (e.g. "assets/images/logo_tesla", no extension),
/// caches the resolved path for the lifetime of the app so the bundle is
/// only probed once per logo, and falls back to the plain bolt icon if
/// none of the supported extensions are found (or the file isn't
/// registered in pubspec.yaml yet).
class _EvLogoImage extends StatefulWidget {
  final String baseName;
  final double size;
  final double scale;
  final Alignment alignment;
  final Color fallbackColor;

  const _EvLogoImage({
    required this.baseName,
    required this.size,
    required this.scale,
    required this.alignment,
    required this.fallbackColor,
  });

  @override
  State<_EvLogoImage> createState() => _EvLogoImageState();
}

class _EvLogoImageState extends State<_EvLogoImage> {
  static final Map<String, String?> _resolvedCache = {};
  static const _extensions = ['png', 'jpg', 'jpeg', 'webp'];

  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<String?> _resolve() async {
    if (_resolvedCache.containsKey(widget.baseName)) {
      return _resolvedCache[widget.baseName];
    }
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
          return Icon(Icons.ev_station_rounded, color: widget.fallbackColor, size: widget.size * 0.48);
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
                Icon(Icons.ev_station_rounded, color: widget.fallbackColor, size: widget.size * 0.48),
          ),
        );
      },
    );
  }
}

class _EvBrandIdentity {
  final Color background;
  final String? logoBaseName; // asset path WITHOUT extension
  final double logoScale;
  final Alignment logoAlignment;
  const _EvBrandIdentity(
    this.background, {
    this.logoBaseName,
    this.logoScale = 1,
    this.logoAlignment = Alignment.center,
  });

  factory _EvBrandIdentity.from(EVCharger charger) {
    final raw = charger.operatorName?.trim().isNotEmpty == true
        ? charger.operatorName!
        : charger.name;
    final network = normaliseEvOperator(raw) ?? raw;
    final value = network.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (value.contains('tesla')) {
      return const _EvBrandIdentity(
        Color(0xFFCC0000),
        logoBaseName: 'assets/images/logo_tesla',
        logoScale: 1.3,
      );
    }
    if (value.contains('gentari')) {
      return const _EvBrandIdentity(
        Color(0xFF00463C),
        logoBaseName: 'assets/images/logo_gentari',
        logoScale: 1.25,
      );
    }
    if (value.contains('chargev')) {
      return const _EvBrandIdentity(
        Color(0xFFF7941D),
        logoBaseName: 'assets/images/logo_chargev',
        logoScale: 1.3,
      );
    }
    if (value.contains('jomcharge')) {
      return const _EvBrandIdentity(
        Color(0xFF2F6FED),
        logoBaseName: 'assets/images/logo_jomcharge',
        logoScale: 1.3,
      );
    }
    if (value.contains('dchub')) {
      return const _EvBrandIdentity(
        Color(0xFF6A3FA0),
        logoBaseName: 'assets/images/logo_dchub',
        logoScale: 1.3,
      );
    }
    if (value.contains('shellrecharge')) {
      return const _EvBrandIdentity(
        Color(0xFFFFD500),
        logoBaseName: 'assets/images/logo_shell',
        logoScale: 1.4,
        logoAlignment: Alignment.topCenter,
      );
    }
    if (value.contains('chargesini')) {
      return const _EvBrandIdentity(
        Color(0xFF1FA774),
        logoBaseName: 'assets/images/logo_chargesini',
        logoScale: 1.3,
      );
    }
    if (value.contains('evduty')) {
      return const _EvBrandIdentity(
        Color(0xFF0E1F63),
        logoBaseName: 'assets/images/logo_evduty',
        logoScale: 1.3,
      );
    }
    if (value.contains('bmwcharging') || value.contains('bmw')) {
      return const _EvBrandIdentity(
        Color(0xFF1C69D4),
        logoBaseName: 'assets/images/logo_bmw',
        logoScale: 1.25,
      );
    }
    if (value.contains('porsche')) {
      return const _EvBrandIdentity(
        Color(0xFF000000),
        logoBaseName: 'assets/images/logo_porsche',
        logoScale: 1.2,
      );
    }

    // Unrecognised operator — fall back to the same deterministic
    // per-name colour used elsewhere in the app (colorForName, from
    // models.dart), with no logo, so the plain icon shows instead.
    return _EvBrandIdentity(colorForName(raw));
  }
}
