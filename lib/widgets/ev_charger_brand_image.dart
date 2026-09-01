import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
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
    if (value.contains('chargEV')) {
      return const _EvBrandIdentity(
        Color(0xFF2F6FED),
        logoBaseName: 'assets/images/logo_chargev',
        logoScale: 1.3,
      );
    }
    if (value.contains('jomcharge')) {
      return const _EvBrandIdentity(
        Color(0xFFF7941D),
        logoBaseName: 'assets/images/logo_jomcharge',
        logoScale: 1.3,
      );
    }
    if (value.contains('dchandal')) {
      return const _EvBrandIdentity(
        Color(0xFF6A3FA0),
        logoBaseName: 'assets/images/logo_dchandal',
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
    if (value.contains('bmwcharging') || value.contains('bmw')) {
      return const _EvBrandIdentity(
        Color(0xFF1C69D4),
        logoBaseName: 'assets/images/logo_bmw',
        logoScale: 1.25,
      );
    }
    if (value.contains('evguru')) {
      return const _EvBrandIdentity(
        Color(0xFF6A3FA0),
        logoBaseName: 'assets/images/logo_evguru',
        logoScale: 1.3,
      );
    }

    // Unrecognised operator — fall back to the same deterministic
    // per-name colour used elsewhere in the app (colorForName, from
    // models.dart), with no logo, so the plain icon shows instead.
    return _EvBrandIdentity(colorForName(raw));
  }
}

class EVChargerBrandImage extends StatefulWidget {
  final EVCharger charger;
  final bool compact;

  const EVChargerBrandImage({
    super.key,
    required this.charger,
    this.compact = false,
  });

  @override
  State<EVChargerBrandImage> createState() => _EVChargerBrandImageState();
}

class _EVChargerBrandImageState extends State<EVChargerBrandImage> {
  static const double _placeholderAspectRatio = 16 / 9;
  static final Map<String, String?> _assetPathCache = {};
  static const _extensions = ['png', 'jpg', 'jpeg', 'webp'];

  ImageProvider? _provider;
  double? _aspectRatio;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EVChargerBrandImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.charger.operatorName != widget.charger.operatorName ||
        oldWidget.charger.name != widget.charger.name) {
      setState(() {
        _provider = null;
        _aspectRatio = null;
      });
      _load();
    }
  }

  String _baseNameFor(String brand) {
    final value = brand.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    if (value.contains('tesla')) {
      return 'assets/images/station_tesla';
    }
    if (value.contains('gentari')) {
      return 'assets/images/station_gentari';
    }
    if (value.contains('chargEV')) {
      return 'assets/images/station_chargeEV';
    }
    if (value.contains('jomcharge')) {
      return 'assets/images/station_jomcharge';
    }
    if (value.contains('dchandal')) {
      return 'assets/images/station_dchandal';
    }
    if (value.contains('shellrecharge')) {
      return 'assets/images/station_shellrecharge';
    }
    if (value.contains('chargesini')) {
      return 'assets/images/station_chargesini';
    }
    if (value.contains('bmwcharging') || value.contains('bmw')) {
      return 'assets/images/station_bmw';
    }
    if (value.contains('evguru') || value.contains('bmw')) {
      return 'assets/images/station_evguru';
    }

    return 'assets/images/ev_charger_fallback';
  }

  Future<String?> _resolveLocalPath(String baseName) async {
    if (_assetPathCache.containsKey(baseName)) {
      return _assetPathCache[baseName];
    }

    for (final ext in _extensions) {
      final path = '$baseName.$ext';

      try {
        await rootBundle.load(path);
        _assetPathCache[baseName] = path;
        return path;
      } catch (_) {}
    }

    _assetPathCache[baseName] = null;
    return null;
  }

  Future<void> _load() async {
    final token = ++_loadToken;

    final raw = widget.charger.operatorName?.trim().isNotEmpty == true
        ? widget.charger.operatorName!
        : widget.charger.name;

    // Use the bundled operator/station image.
    final localPath = await _resolveLocalPath(_baseNameFor(raw.trim()));

    if (token != _loadToken) return;

    if (localPath != null) {
      await _tryProvider(
        AssetImage(localPath),
        token,
      );
    }
  }

  Future<bool> _tryProvider(
      ImageProvider provider,
      int token,
      ) {
    final completer = Completer<bool>();
    final stream = provider.resolve(const ImageConfiguration());

    late final ImageStreamListener listener;

    listener = ImageStreamListener(
          (info, _) {
        stream.removeListener(listener);

        if (token != _loadToken) {
          if (!completer.isCompleted) {
            completer.complete(true);
          }
          return;
        }

        final width = info.image.width.toDouble();
        final height = info.image.height.toDouble();

        if (mounted) {
          setState(() {
            _provider = provider;
            _aspectRatio = height > 0 ? width / height : null;
          });
        }

        if (!completer.isCompleted) {
          completer.complete(true);
        }
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);

        if (!completer.isCompleted) {
          completer.complete(false);
        }
      },
    );

    stream.addListener(listener);

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final charger = widget.charger;

    final brand = charger.operatorName?.trim().isNotEmpty == true
        ? charger.operatorName!
        : charger.name;

    final identity = _EvBrandIdentity.from(charger);
    final brandColor = identity.background;

    final onBrandColor =
    brandColor.computeLuminance() > 0.55
        ? Colors.black87
        : Colors.white;

    return AspectRatio(
      aspectRatio: _aspectRatio ?? _placeholderAspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_provider != null)
            Image(
              image: _provider!,
              fit: BoxFit.cover,
            )
          else
            Container(
              color: brandColor.withValues(alpha: 0.85),
              alignment: Alignment.center,
              child: Icon(
                Icons.ev_station_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 64,
              ),
            ),

          if (widget.compact)
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
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 3,
                    ),
                  ],
                ),
              ),
            )
          else
            Positioned(
              left: 18,
              bottom: 16,
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 260,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: brandColor,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
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
      ),
    );
  }
}