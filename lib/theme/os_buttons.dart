import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme.dart';

/// Wraps any widget with a springy "press down" scale + light haptic tick.
/// Purely visual: it only calls [onTap] / [onLongPress] you give it.
class OsPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  const OsPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = .96,
    this.haptic = true,
  });

  @override
  State<OsPressable> createState() => _OsPressableState();
}

class _OsPressableState extends State<OsPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => _set(true) : null,
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

enum OsBtnKind { primary, secondary, outline, danger, ghost }

/// The one button style for the app. Same API shape as a normal button:
/// label, optional icon, busy spinner, disabled when onPressed is null.
class OsButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool iconAfter;
  final OsBtnKind kind;
  final double height;

  const OsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.iconAfter = false,
    this.kind = OsBtnKind.primary,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    Color fg;
    Gradient? gradient;
    Color? fill;
    Border? border;
    List<BoxShadow> shadow = const [];

    switch (kind) {
      case OsBtnKind.primary:
        fg = Colors.white;
        gradient = OsColors.brandGradient;
        border = Border.all(color: Colors.white.withValues(alpha: .14));
        shadow = [
          BoxShadow(
            color: OsColors.purpleDeep.withValues(alpha: enabled ? .42 : .15),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ];
        break;
      case OsBtnKind.danger:
        fg = Colors.white;
        gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF5A7A), Color(0xFFD7263D)],
        );
        border = Border.all(color: Colors.white.withValues(alpha: .12));
        shadow = [
          BoxShadow(
            color: const Color(0xFFD7263D).withValues(alpha: enabled ? .35 : .12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ];
        break;
      case OsBtnKind.secondary:
        fg = const Color(0xFFD9CCFF);
        fill = OsColors.purple.withValues(alpha: .16);
        border = Border.all(color: OsColors.purple.withValues(alpha: .38));
        break;
      case OsBtnKind.outline:
        fg = OsColors.text;
        fill = OsColors.surface.withValues(alpha: .6);
        border = Border.all(color: OsColors.border, width: 1.3);
        break;
      case OsBtnKind.ghost:
        fg = OsColors.muted;
        break;
    }

    final content = busy
        ? SizedBox(
            width: 21,
            height: 21,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null && !iconAfter) ...[
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    letterSpacing: .1,
                  ),
                ),
              ),
              if (icon != null && iconAfter) ...[
                const SizedBox(width: 8),
                Icon(icon, color: fg, size: 20),
              ],
            ],
          );

    return Opacity(
      opacity: enabled || busy ? 1 : .5,
      child: OsPressable(
        onTap: enabled ? onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: expand ? 16 : 22),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient,
            color: fill,
            borderRadius: BorderRadius.circular(height / 2.6),
            border: border,
            boxShadow: shadow,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Round glass icon button (optionally highlighted or with a small badge).
class OsIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final int badge;
  final double size;

  const OsIconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.active = false,
    this.badge = 0,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn = OsPressable(
      onTap: onPressed,
      scale: .9,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active ? OsColors.brandGradient : null,
          color: active ? null : OsColors.surface2.withValues(alpha: .9),
          border: Border.all(
            color: active ? Colors.white.withValues(alpha: .18) : OsColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: size * .48,
          color: onPressed == null
              ? OsColors.muted.withValues(alpha: .5)
              : (active ? Colors.white : OsColors.text),
        ),
      ),
    );
    if (badge > 0) {
      btn = Badge(
        label: Text('$badge'),
        backgroundColor: OsColors.coral,
        child: btn,
      );
    }
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Selectable pill (filters, quick actions).
class OsPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  const OsPill({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OsPressable(
      onTap: onTap,
      scale: .94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? OsColors.brandGradient : null,
          color: selected ? null : OsColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? Colors.white.withValues(alpha: .16) : OsColors.border,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? Colors.white : OsColors.purple),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : OsColors.text,
            ),
          ),
        ]),
      ),
    );
  }
}
