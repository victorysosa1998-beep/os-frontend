import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'os_buttons.dart';

/// Big friendly screen header used at the top of Feed, Discover, Chats, You.
class OsScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final EdgeInsets padding;

  const OsScreenHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 18),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: Padding(
        padding: padding,
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: OsColors.brandGradient,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: OsColors.purpleDeep.withValues(alpha: .4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.8,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: OsColors.muted, fontSize: 13, height: 1.3),
              ),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
  }
}

/// Section heading with a small gradient accent bar.
class OsSectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;

  const OsSectionTitle(
    this.title, {
    super.key,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.only(top: 6, bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [
        Container(
          width: 5,
          height: 20,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF8B5CF6), Color(0xFFFF6B7A)],
            ),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 10),
        if (icon != null) ...[
          Icon(icon, size: 19, color: OsColors.purple),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -.3),
          ),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// One destination of [OsFloatingNavBar].
class OsNavItem {
  final Widget Function(bool selected) icon;
  final String label;
  const OsNavItem({required this.icon, required this.label});
}

/// Floating, rounded bottom navigation with an animated gradient indicator.
class OsFloatingNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<OsNavItem> items;

  const OsFloatingNavBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          decoration: BoxDecoration(
            color: OsColors.surface.withValues(alpha: .97),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: OsColors.border.withValues(alpha: .9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .45),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: OsPressable(
                  scale: .9,
                  onTap: () => onChanged(i),
                  child: _NavCell(item: items[i], selected: i == index),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _NavCell extends StatelessWidget {
  final OsNavItem item;
  final bool selected;
  const _NavCell({required this.item, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: selected ? 58 : 40,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? OsColors.brandGradient : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: OsColors.purpleDeep.withValues(alpha: .45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: IconTheme(
          data: IconThemeData(
            size: 23,
            color: selected ? Colors.white : OsColors.muted,
          ),
          child: item.icon(selected),
        ),
      ),
      const SizedBox(height: 3),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          item.label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            color: selected ? OsColors.text : OsColors.muted,
          ),
        ),
      ),
    ]);
  }
}

/// One step of the "Get started" checklist.
class OsStep {
  final IconData icon;
  final String title;
  final bool done;
  final VoidCallback? onTap;
  const OsStep({required this.icon, required this.title, required this.done, this.onTap});
}

/// Progress checklist that guides new members through the app's flow.
/// Hides itself once every step is done.
class OsGetStartedCard extends StatelessWidget {
  final List<OsStep> steps;
  const OsGetStartedCard({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    final doneCount = steps.where((s) => s.done).length;
    if (steps.isEmpty || doneCount == steps.length) return const SizedBox.shrink();
    final progress = doneCount / steps.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OsColors.border.withValues(alpha: .8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.rocket_launch_rounded, color: OsColors.amber, size: 22),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Get started',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            '$doneCount of ${steps.length}',
            style: const TextStyle(color: OsColors.muted, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 7,
              backgroundColor: OsColors.surface2,
              valueColor: const AlwaysStoppedAnimation(OsColors.purple),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final s in steps)
          OsPressable(
            onTap: s.done ? null : s.onTap,
            scale: .98,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: s.done ? const Color(0xFF2ECC9A).withValues(alpha: .2) : OsColors.surface2,
                  ),
                  child: Icon(
                    s.done ? Icons.check_rounded : s.icon,
                    size: 18,
                    color: s.done ? const Color(0xFF2ECC9A) : OsColors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: s.done ? OsColors.muted : OsColors.text,
                      decoration: s.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (!s.done)
                  const Icon(Icons.chevron_right_rounded, color: OsColors.muted),
              ]),
            ),
          ),
      ]),
    );
  }
}
