import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared design tokens and reusable widgets so every screen uses the same
/// spacing scale, corner radius, and state patterns instead of each screen
/// picking its own numbers. These widgets read colors through
/// `Theme.of(context)` rather than the fixed `AppColors` constants, so any
/// screen that adopts them automatically supports dark mode too.

/// Spacing scale — use these instead of ad-hoc numbers in SizedBox/padding.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Corner radius scale. `card` (14) matches what was already the most
/// common value across the app, so adopting it everywhere is a
/// low-risk convergence rather than a new look.
class AppRadius {
  static const double chip = 20.0;
  static const double small = 10.0;
  static const double card = 14.0;
  static const double large = 18.0;
  static const double sheet = 24.0;
}

/// Standard card container — border + radius + padding all drawn from the
/// shared scale, colored from the active theme so it darkens correctly.
/// Optional [onTap] wraps it in a Material+InkWell so it still shows a
/// ripple, matching how tappable cards behaved before.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderRadius? borderRadius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = borderRadius ?? BorderRadius.circular(AppRadius.card);
    return Container(
      decoration: BoxDecoration(
        color: color ?? theme.cardColor,
        borderRadius: radius,
        border: Border.all(color: theme.dividerColor),
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
  }
}

/// A section title used above a group of cards — bold, consistent size,
/// optional trailing action (e.g. "See all", a refresh icon).
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The bold 24px page title row used on top-level tabs (Home, Favourite,
/// Profile, ...), with an optional trailing action like a refresh button.
class PageTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PageTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? AppColors.textDark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Consistent "nothing here yet" state — icon, title, optional message,
/// optional action. Replaces each screen writing its own Column/Icon/Text.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyLarge?.color ?? AppColors.textDark;
    final mutedColor = theme.disabledColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: mutedColor),
            const SizedBox(height: AppSpacing.md),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(message!,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: mutedColor, height: 1.4)),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Consistent centered loading state — spinner with an optional caption,
/// instead of a bare CircularProgressIndicator with no context.
class AppLoadingState extends StatelessWidget {
  final String? message;
  const AppLoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(message!, style: TextStyle(color: Theme.of(context).disabledColor, fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}

/// Consistent "something went wrong" state with a retry button, so every
/// screen's network-failure UI looks and behaves the same way.
class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const AppErrorState({
    super.key,
    this.message = 'Something went wrong. Please try again.',
    this.onRetry,
    this.icon = Icons.wifi_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final mutedColor = Theme.of(context).disabledColor;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: mutedColor),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: mutedColor, fontSize: 13)),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small amber inline notice banner — used for non-blocking warnings like
/// "some data couldn't load". Standardises the ad-hoc amber Containers
/// that appeared with slightly different padding/radius in different
/// screens. The amber background is intentionally the same in both modes
/// (it's a caution color, not a surface color) — only the text color
/// adapts so it stays readable.
class AppNoticeBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color background;

  const AppNoticeBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.background = const Color(0xFFFFF3CD),
  });

  @override
  Widget build(BuildContext context) {
    // Amber banner text needs to stay dark for contrast against the amber
    // background regardless of app-wide theme, so this one intentionally
    // does NOT follow Theme.of(context) text color.
    const textColor = Color(0xFF3D2E00);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 11.5, color: textColor, height: 1.4))),
        ],
      ),
    );
  }
}
