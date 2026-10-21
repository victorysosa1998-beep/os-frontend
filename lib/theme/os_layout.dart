import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Shared breakpoints so every screen adapts the same way.
class OsBreakpoints {
  static const double tablet = 600;
  static const double wide = 900;

  static bool isTablet(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= wide;
}

/// Number of grid columns for a given available width.
int osGridCount(double width, {double minTile = 170, int min = 2, int max = 6}) =>
    math.max(min, math.min(max, (width / minTile).floor()));

/// Centers content and caps its width on tablets / desktop / landscape, while
/// staying full-width on phones. Wrap form-like pages (auth, settings, hubs).
class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 640});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

/// App-wide wrapper used from MaterialApp.builder:
///  * clamps text scale so large system fonts never overflow layouts
///  * caps the app width on very wide screens and paints a matching backdrop
class OsAppFrame extends StatelessWidget {
  final Widget? child;
  const OsAppFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final scaler = mq.textScaler.clamp(minScaleFactor: .85, maxScaleFactor: 1.25);
    return MediaQuery(
      data: mq.copyWith(textScaler: scaler),
      child: ColoredBox(
        color: OsColors.bg,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
