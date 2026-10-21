import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'os_buttons.dart';

/// Soft glowing brand background used on splash, onboarding and auth.
class OsBackground extends StatelessWidget {
  final Widget child;
  const OsBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: OsColors.bg)),
        Positioned(
          top: -140,
          left: -100,
          child: _Glow(color: OsColors.purpleDeep.withValues(alpha: .38), size: 340),
        ),
        Positioned(
          bottom: -160,
          right: -120,
          child: _Glow(color: OsColors.coral.withValues(alpha: .22), size: 360),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// OS logo mark: launcher asset if present, gradient "os" tile otherwise.
class OsLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;
  const OsLogo({super.key, this.size = 64, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: Image.asset(
        'assets/icon/os_launcher.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: const BoxDecoration(gradient: OsColors.brandGradient),
          child: Text(
            'os',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * .46,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
    );
    if (!showWordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * .22),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('os',
                style: TextStyle(
                    fontSize: size * .48, fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(height: 3),
            const Text('REAL CONNECTIONS',
                style: TextStyle(fontSize: 9, letterSpacing: 1.4, color: OsColors.muted)),
          ],
        ),
      ],
    );
  }
}

/// Gradient primary button (now backed by the shared [OsButton] look).
class OsGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  const OsGradientButton(
      {super.key, required this.label, this.onPressed, this.busy = false, this.icon});

  @override
  Widget build(BuildContext context) => OsButton(
        label: label,
        onPressed: onPressed,
        busy: busy,
        icon: icon,
        iconAfter: true,
        height: 56,
      );
}

/// Standard card surface.
class OsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  const OsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        decoration: BoxDecoration(
          color: OsColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: OsColors.border.withValues(alpha: .7)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            splashColor: OsColors.purple.withValues(alpha: .12),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}
