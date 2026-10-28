import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen size classes. The app re-lays itself out when the window changes
/// (rotate a phone, resize the browser, snap a window).
enum ScreenSize {
  phone, // under 600 px wide
  tablet, // 600 - 1023
  laptop, // 1024 - 1439
  desktop, // 1440 and up
}

class Responsive {
  Responsive._();

  static const double tabletFrom = 600;
  static const double laptopFrom = 1024;
  static const double desktopFrom = 1440;

  /// Side navigation (instead of bottom bar) starts here.
  static const double railFrom = 800;

  /// Navigation rail with text beside the icons starts here.
  static const double extendedRailFrom = 1200;

  static ScreenSize of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= desktopFrom) return ScreenSize.desktop;
    if (w >= laptopFrom) return ScreenSize.laptop;
    if (w >= tabletFrom) return ScreenSize.tablet;
    return ScreenSize.phone;
  }

  /// Widest a form / detail page may be (phones use the full width).
  static double formWidth(BuildContext context) {
    switch (of(context)) {
      case ScreenSize.phone:
        return double.infinity;
      case ScreenSize.tablet:
        return 640;
      case ScreenSize.laptop:
        return 720;
      case ScreenSize.desktop:
        return 780;
    }
  }

  /// Widest the main tab pages (lists, dashboard) may be.
  static double pageWidth(BuildContext context) {
    switch (of(context)) {
      case ScreenSize.phone:
      case ScreenSize.tablet:
        return double.infinity;
      case ScreenSize.laptop:
        return 1100;
      case ScreenSize.desktop:
        return 1280;
    }
  }

  /// Adds equal side space so content stays centred at [maxWidth] while the
  /// scroll area (and its scroll bar) still spans the whole window.
  static EdgeInsets pad(
    BuildContext context,
    double maxWidth,
    EdgeInsets base,
  ) {
    if (maxWidth.isInfinite) return base;
    final w = MediaQuery.sizeOf(context).width;
    final side = math.max(0.0, (w - maxWidth) / 2);
    return EdgeInsets.fromLTRB(
      math.max(base.left, side),
      base.top,
      math.max(base.right, side),
      base.bottom,
    );
  }
}

/// Centres [child] and stops it growing wider than [maxWidth].
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (maxWidth.isInfinite) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
