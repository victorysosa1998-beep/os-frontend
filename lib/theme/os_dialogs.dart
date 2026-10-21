import 'package:flutter/material.dart';
import 'app_theme.dart';

enum OsActionKind { primary, secondary, danger }

class OsPopupAction {
  final String label;
  final IconData? icon;
  final OsActionKind kind;
  final Object? result;
  final Object? Function()? resultBuilder; // evaluated at tap time (e.g. a text field value)
  final VoidCallback? onTap;
  const OsPopupAction(this.label,
      {this.icon, this.kind = OsActionKind.secondary, this.result, this.resultBuilder, this.onTap});
}

/// Polished in-app popup: gradient hero, big icon, title, message, optional
/// custom body and a row (or stack, on narrow widths) of actions.
class OsPopup extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? body;
  final List<OsPopupAction> actions;
  final List<Color> colors;
  final Widget? hero;

  const OsPopup({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.body,
    this.actions = const [],
    this.colors = const [Color(0xFF8B5CF6), Color(0xFFFF6B7A)],
    this.hero,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * .86;
    return Dialog(
      backgroundColor: OsColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: OsColors.border.withValues(alpha: .8)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxH),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
              child: Column(children: [
                hero ??
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 2),
                      ),
                      child: Icon(icon, color: Colors.white, size: 36),
                    ),
                const SizedBox(height: 14),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.2)),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45)),
                ],
              ]),
            ),
            if (body != null)
              Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 0), child: body),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(18),
                child: LayoutBuilder(builder: (context, c) {
                  final buttons = [for (final a in actions) _button(context, a)];
                  if (actions.length <= 2 && c.maxWidth > 300) {
                    return Row(children: [
                      for (var i = 0; i < buttons.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: buttons[i]),
                      ]
                    ]);
                  }
                  return Column(children: [
                    for (var i = 0; i < buttons.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: buttons[i]),
                    ]
                  ]);
                }),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _button(BuildContext context, OsPopupAction a) {
    void tap() {
      Navigator.of(context).pop(a.resultBuilder != null ? a.resultBuilder!() : a.result);
      a.onTap?.call();
    }

    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (a.icon != null) ...[Icon(a.icon, size: 18), const SizedBox(width: 6)],
      Flexible(child: Text(a.label, overflow: TextOverflow.ellipsis)),
    ]);
    switch (a.kind) {
      case OsActionKind.primary:
        return FilledButton(onPressed: tap, child: child);
      case OsActionKind.danger:
        return FilledButton(
          onPressed: tap,
          style: FilledButton.styleFrom(backgroundColor: OsColors.coral, foregroundColor: Colors.white),
          child: child,
        );
      case OsActionKind.secondary:
        return OutlinedButton(onPressed: tap, child: child);
    }
  }
}

/// Animated presentation for any popup (fade + gentle scale).
Future<T?> showOsPopup<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: .62),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, __) => SafeArea(child: Center(child: builder(ctx))),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(scale: Tween<double>(begin: .88, end: 1).animate(curved), child: child),
        );
      },
    );

/// Confirmation popup. Returns true when the user confirms.
Future<bool> osConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool danger = false,
}) async {
  final r = await showOsPopup<bool>(
    context,
    builder: (_) => OsPopup(
      icon: icon,
      title: title,
      message: message,
      colors: danger
          ? const [Color(0xFFB4233C), Color(0xFFFF6B7A)]
          : const [Color(0xFF8B5CF6), Color(0xFFFF6B7A)],
      actions: [
        OsPopupAction(cancelLabel, result: false),
        OsPopupAction(confirmLabel,
            result: true, kind: danger ? OsActionKind.danger : OsActionKind.primary),
      ],
    ),
  );
  return r == true;
}

/// Simple info popup with a single "Got it" button.
Future<void> osInfo(BuildContext context,
    {required String title, required String message, IconData icon = Icons.info_outline_rounded}) async {
  await showOsPopup<void>(
    context,
    builder: (_) => OsPopup(
      icon: icon,
      title: title,
      message: message,
      actions: const [OsPopupAction('Got it', kind: OsActionKind.primary)],
    ),
  );
}

/// Full incoming-call popup. Returns true = accept, false = decline, null =
/// closed programmatically (caller hung up). [onBuilt] receives the dialog
/// context so the caller can close it when the call is cancelled remotely.
Future<bool?> showIncomingCallPopup(
  BuildContext context, {
  required String name,
  required bool video,
  required Widget avatar,
  required void Function(BuildContext dialogContext) onBuilt,
}) =>
    showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Incoming call',
      barrierColor: Colors.black.withValues(alpha: .85),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (ctx, _, __) {
        onBuilt(ctx);
        return _IncomingCallBody(name: name, video: video, avatar: avatar);
      },
      transitionBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .12), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      ),
    );

class _IncomingCallBody extends StatefulWidget {
  final String name;
  final bool video;
  final Widget avatar;
  const _IncomingCallBody({required this.name, required this.video, required this.avatar});

  @override
  State<_IncomingCallBody> createState() => _IncomingCallBodyState();
}

class _IncomingCallBodyState extends State<_IncomingCallBody> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _round(IconData icon, String label, Color color, bool result) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: color,
            shape: const CircleBorder(),
            elevation: 6,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(result),
              child: SizedBox(width: 72, height: 72, child: Icon(icon, color: Colors.white, size: 32)),
            ),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2B1A5C), Color(0xFF100D1F)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
                  child: Column(children: [
                    Text(widget.video ? 'INCOMING VIDEO CALL' : 'INCOMING AUDIO CALL',
                        style: const TextStyle(
                            color: Colors.white70, letterSpacing: 1.6, fontSize: 12, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, child) => Stack(alignment: Alignment.center, children: [
                          for (final o in [0.0, .5])
                            Builder(builder: (_) {
                              final v = (_pulse.value + o) % 1.0;
                              return Container(
                                width: 130 + 90 * v,
                                height: 130 + 90 * v,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: OsColors.purple.withValues(alpha: (1 - v) * .7), width: 3),
                                ),
                              );
                            }),
                          child!,
                        ]),
                        child: widget.avatar,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(widget.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text(widget.video ? 'wants to video chat on OS' : 'is calling you on OS',
                        style: const TextStyle(color: Colors.white70, fontSize: 15)),
                    const Spacer(),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _round(Icons.call_end_rounded, 'Decline', const Color(0xFFE54555), false),
                      _round(widget.video ? Icons.videocam_rounded : Icons.call_rounded, 'Accept',
                          const Color(0xFF22B573), true),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
