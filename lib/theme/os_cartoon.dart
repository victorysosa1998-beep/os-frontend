import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Illustrated scenes used on the onboarding slideshow, feature tour and the
/// features hub. Everything is drawn with Flutter's canvas, so there are no
/// real photos of people, no remote downloads and nothing to fail offline.
enum CartoonScene { verified, discover, chat, voice, safety }

class CartoonSceneView extends StatefulWidget {
  final CartoonScene scene;
  final BorderRadius borderRadius;
  const CartoonSceneView({
    super.key,
    required this.scene,
    this.borderRadius = const BorderRadius.all(Radius.circular(30)),
  });

  @override
  State<CartoonSceneView> createState() => _CartoonSceneViewState();
}

class _CartoonSceneViewState extends State<CartoonSceneView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<Color> get _bg {
    switch (widget.scene) {
      case CartoonScene.verified:
        return const [Color(0xFF5B34C9), Color(0xFFB04CD9)];
      case CartoonScene.discover:
        return const [Color(0xFF7C3AED), Color(0xFFFF6B7A)];
      case CartoonScene.chat:
        return const [Color(0xFF3B2A8F), Color(0xFF8B5CF6)];
      case CartoonScene.voice:
        return const [Color(0xFF8B2F9E), Color(0xFFFF7185)];
      case CartoonScene.safety:
        return const [Color(0xFF1F6F8B), Color(0xFF8B5CF6)];
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: widget.borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _bg,
            ),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _ScenePainter(widget.scene, _c.value),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
}

enum _Hair { short, long, bun, afro }

class _ScenePainter extends CustomPainter {
  final CartoonScene scene;
  final double t; // 0..1 looping
  _ScenePainter(this.scene, this.t);

  double get _wave => math.sin(t * math.pi * 2);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final u = math.min(w, h);
    canvas.clipRect(Offset.zero & size);

    _backdrop(canvas, size, u);

    // Characters — diverse skin tones and styles, shoulders cut by the frame.
    _person(canvas, Offset(w * .29, h * .60 + _wave * u * .006), u * .15,
        skin: const Color(0xFF8D5524),
        hair: const Color(0xFF1B1030),
        shirt: const Color(0xFFFF7185),
        style: _Hair.long,
        facingRight: true);
    _person(canvas, Offset(w * .71, h * .60 - _wave * u * .006), u * .15,
        skin: const Color(0xFFC68642),
        hair: const Color(0xFF2A1B3D),
        shirt: const Color(0xFF9B7BFF),
        style: _Hair.short,
        facingRight: false);

    switch (scene) {
      case CartoonScene.verified:
        _shield(canvas, Offset(w * .5, h * .27), u * .17);
        break;
      case CartoonScene.discover:
        _pin(canvas, Offset(w * .5, h * .27), u * .15);
        _dots(canvas, Offset(w * .36, h * .40), Offset(w * .47, h * .30), Offset(w * .28, h * .26));
        _dots(canvas, Offset(w * .64, h * .40), Offset(w * .53, h * .30), Offset(w * .72, h * .26));
        break;
      case CartoonScene.chat:
        _bubble(canvas, Rect.fromCenter(center: Offset(w * .30, h * .24), width: u * .42, height: u * .22),
            Colors.white, tailLeft: true, dots: true);
        _bubble(canvas, Rect.fromCenter(center: Offset(w * .70, h * .20), width: u * .42, height: u * .22),
            const Color(0xFFFF7185), tailLeft: false, heart: true);
        break;
      case CartoonScene.voice:
        _waveform(canvas, Offset(w * .5, h * .27), u * .30);
        break;
      case CartoonScene.safety:
        _shield(canvas, Offset(w * .5, h * .27), u * .17, heart: true);
        break;
    }

    _floatingHearts(canvas, size, u);
  }

  void _backdrop(Canvas canvas, Size size, double u) {
    final w = size.width, h = size.height;
    final soft = Paint()..color = Colors.white.withValues(alpha: .08);
    canvas.drawCircle(Offset(w * .12, h * .18), u * .28, soft);
    canvas.drawCircle(Offset(w * .92, h * .78), u * .36, soft);
    // clouds
    final cloud = Paint()..color = Colors.white.withValues(alpha: .14);
    void puff(double x, double y, double s) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: s, height: s * .42), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x - s * .22, y - s * .1), width: s * .5, height: s * .4), cloud);
      canvas.drawOval(Rect.fromCenter(center: Offset(x + s * .2, y - s * .08), width: s * .42, height: s * .34), cloud);
    }

    puff(w * .16 + _wave * 6, h * .12, u * .30);
    puff(w * .84 - _wave * 6, h * .10, u * .24);
    // sparkles
    final sp = Paint()..color = Colors.white.withValues(alpha: .55 + .3 * _wave.abs());
    for (final o in [Offset(w * .08, h * .46), Offset(w * .94, h * .42), Offset(w * .5, h * .06)]) {
      canvas.drawCircle(o, u * .008 + u * .004 * _wave.abs(), sp);
    }
    // ground glow
    canvas.drawRect(
      Rect.fromLTWH(0, h * .86, w, h * .14),
      Paint()..color = Colors.black.withValues(alpha: .12),
    );
  }

  Path _heartPath(Offset c, double s) {
    final p = Path();
    p.moveTo(c.dx, c.dy + s * .35);
    p.cubicTo(c.dx - s * 1.0, c.dy - s * .35, c.dx - s * .45, c.dy - s * .95, c.dx, c.dy - s * .4);
    p.cubicTo(c.dx + s * .45, c.dy - s * .95, c.dx + s * 1.0, c.dy - s * .35, c.dx, c.dy + s * .35);
    p.close();
    return p;
  }

  void _floatingHearts(Canvas canvas, Size size, double u) {
    final w = size.width, h = size.height;
    for (var i = 0; i < 5; i++) {
      final phase = (t + i * .2) % 1.0;
      final x = w * (.30 + i * .10) + math.sin(phase * math.pi * 2 + i) * u * .03;
      final y = h * (.58 - phase * .42);
      final a = (1 - phase).clamp(0.0, 1.0) * .9;
      canvas.drawPath(
        _heartPath(Offset(x, y), u * (.028 + (i % 3) * .008)),
        Paint()..color = (i.isEven ? const Color(0xFFFFD1DC) : Colors.white).withValues(alpha: a),
      );
    }
  }

  void _person(
    Canvas c,
    Offset head,
    double r, {
    required Color skin,
    required Color hair,
    required Color shirt,
    required _Hair style,
    required bool facingRight,
  }) {
    final dir = facingRight ? 1.0 : -1.0;
    final hairPaint = Paint()..color = hair;
    final skinPaint = Paint()..color = skin;

    // hair behind head
    switch (style) {
      case _Hair.long:
        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: head.translate(0, r * .75), width: r * 2.45, height: r * 2.9),
            Radius.circular(r),
          ),
          hairPaint,
        );
        break;
      case _Hair.afro:
        c.drawCircle(head.translate(0, -r * .15), r * 1.28, hairPaint);
        break;
      case _Hair.bun:
        c.drawCircle(head.translate(0, -r * 1.12), r * .42, hairPaint);
        break;
      case _Hair.short:
        break;
    }

    // body / shoulders
    final bodyTop = head.dy + r * 1.15;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(head.dx - r * 1.55, bodyTop, r * 3.1, r * 4),
      topLeft: Radius.circular(r * 1.3),
      topRight: Radius.circular(r * 1.3),
    );
    c.drawRRect(body, Paint()..color = shirt);
    // collar
    c.drawPath(
      Path()
        ..moveTo(head.dx - r * .42, bodyTop)
        ..quadraticBezierTo(head.dx, bodyTop + r * .62, head.dx + r * .42, bodyTop)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: .35),
    );
    // neck
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(head.dx, head.dy + r * 1.0), width: r * .62, height: r * .6),
        Radius.circular(r * .2),
      ),
      skinPaint,
    );

    // head
    c.drawCircle(head, r, skinPaint);
    // ears
    c.drawCircle(head.translate(-r * .98, r * .05), r * .16, skinPaint);
    c.drawCircle(head.translate(r * .98, r * .05), r * .16, skinPaint);

    // hair cap with side-swept fringe
    final cap = Path()
      ..moveTo(head.dx - r * 1.04, head.dy + r * .05)
      ..arcTo(Rect.fromCircle(center: head, radius: r * 1.04), math.pi, math.pi, false)
      ..quadraticBezierTo(head.dx + dir * r * .15, head.dy - r * .52, head.dx - dir * r * .55, head.dy - r * .05)
      ..quadraticBezierTo(head.dx - dir * r * .9, head.dy - r * .3, head.dx - r * 1.04, head.dy + r * .05)
      ..close();
    c.drawPath(cap, hairPaint);

    // face
    final eye = Paint()..color = const Color(0xFF1B1030);
    final look = dir * r * .06;
    c.drawOval(Rect.fromCenter(center: head.translate(-r * .36 + look, r * .08), width: r * .17, height: r * .24), eye);
    c.drawOval(Rect.fromCenter(center: head.translate(r * .36 + look, r * .08), width: r * .17, height: r * .24), eye);
    final shine = Paint()..color = Colors.white;
    c.drawCircle(head.translate(-r * .33 + look, r * .02), r * .04, shine);
    c.drawCircle(head.translate(r * .39 + look, r * .02), r * .04, shine);
    // blush
    final blush = Paint()..color = const Color(0xFFFF7185).withValues(alpha: .38);
    c.drawCircle(head.translate(-r * .58, r * .38), r * .17, blush);
    c.drawCircle(head.translate(r * .58, r * .38), r * .17, blush);
    // smile
    final smile = Paint()
      ..color = const Color(0xFF3B1A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .075
      ..strokeCap = StrokeCap.round;
    c.drawArc(Rect.fromCenter(center: head.translate(look, r * .42), width: r * .5, height: r * .32), .2, math.pi - .4, false, smile);
  }

  void _shield(Canvas c, Offset center, double s, {bool heart = false}) {
    final glow = Paint()
      ..color = Colors.white.withValues(alpha: .18 + .08 * _wave.abs())
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .5);
    c.drawCircle(center, s * 1.1, glow);
    final path = Path()
      ..moveTo(center.dx, center.dy - s)
      ..cubicTo(center.dx + s * .5, center.dy - s * .75, center.dx + s * .85, center.dy - s * .78, center.dx + s * .95, center.dy - s * .7)
      ..cubicTo(center.dx + s * 1.0, center.dy + s * .3, center.dx + s * .5, center.dy + s * .8, center.dx, center.dy + s * 1.05)
      ..cubicTo(center.dx - s * .5, center.dy + s * .8, center.dx - s * 1.0, center.dy + s * .3, center.dx - s * .95, center.dy - s * .7)
      ..cubicTo(center.dx - s * .85, center.dy - s * .78, center.dx - s * .5, center.dy - s * .75, center.dx, center.dy - s)
      ..close();
    c.drawPath(path, Paint()..color = Colors.white);
    c.drawPath(path, Paint()..color = const Color(0xFF70D6FF).withValues(alpha: .28));
    if (heart) {
      c.drawPath(_heartPath(center.translate(0, s * .05), s * .55), Paint()..color = const Color(0xFFFF5A7A));
    } else {
      final check = Paint()
        ..color = const Color(0xFF2BB673)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      c.drawPath(
        Path()
          ..moveTo(center.dx - s * .38, center.dy + s * .02)
          ..lineTo(center.dx - s * .08, center.dy + s * .34)
          ..lineTo(center.dx + s * .42, center.dy - s * .26),
        check,
      );
    }
  }

  void _pin(Canvas c, Offset center, double s) {
    final bob = _wave * s * .06;
    final o = center.translate(0, bob);
    c.drawOval(
      Rect.fromCenter(center: center.translate(0, s * 1.12), width: s * .9 - bob.abs(), height: s * .18),
      Paint()..color = Colors.black.withValues(alpha: .18),
    );
    final path = Path()
      ..moveTo(o.dx, o.dy + s * 1.0)
      ..cubicTo(o.dx - s * 1.0, o.dy + s * .1, o.dx - s * .85, o.dy - s * 1.0, o.dx, o.dy - s * 1.0)
      ..cubicTo(o.dx + s * .85, o.dy - s * 1.0, o.dx + s * 1.0, o.dy + s * .1, o.dx, o.dy + s * 1.0)
      ..close();
    c.drawPath(path, Paint()..color = const Color(0xFFFF4D6D));
    c.drawCircle(o.translate(0, -s * .1), s * .55, Paint()..color = Colors.white);
    c.drawPath(_heartPath(o.translate(0, -s * .1), s * .32), Paint()..color = const Color(0xFFFF4D6D));
  }

  void _dots(Canvas c, Offset a, Offset b, Offset ctrl) {
    final p = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, b.dx, b.dy);
    for (final m in p.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        final pos = m.getTangentForOffset(d)!.position;
        c.drawCircle(pos, 2.2, Paint()..color = Colors.white.withValues(alpha: .75));
      }
    }
  }

  void _bubble(Canvas c, Rect r, Color color, {required bool tailLeft, bool dots = false, bool heart = false}) {
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height * .45));
    c.drawRRect(rr.shift(const Offset(0, 3)), Paint()..color = Colors.black.withValues(alpha: .12));
    c.drawRRect(rr, Paint()..color = color);
    final tx = tailLeft ? r.left + r.width * .22 : r.right - r.width * .22;
    c.drawPath(
      Path()
        ..moveTo(tx - r.height * .16, r.bottom - 1)
        ..lineTo(tx + (tailLeft ? -1 : 1) * r.height * .05, r.bottom + r.height * .3)
        ..lineTo(tx + r.height * .16, r.bottom - 1)
        ..close(),
      Paint()..color = color,
    );
    if (dots) {
      for (var i = 0; i < 3; i++) {
        final k = (t * 3 - i).clamp(0.0, 1.0);
        c.drawCircle(
          Offset(r.center.dx + (i - 1) * r.height * .3, r.center.dy - math.sin(k * math.pi) * 3),
          r.height * .075,
          Paint()..color = OsColors.purple,
        );
      }
    }
    if (heart) {
      c.drawPath(_heartPath(r.center, r.height * .3 + _wave.abs() * 2), Paint()..color = Colors.white);
    }
  }

  void _waveform(Canvas c, Offset center, double width) {
    final bars = 9;
    final gap = width / bars;
    final paint = Paint()
      ..color = Colors.white
      ..strokeCap = StrokeCap.round
      ..strokeWidth = gap * .5;
    for (var i = 0; i < bars; i++) {
      final base = .35 + .65 * math.sin((i + 1) / (bars + 1) * math.pi);
      final amp = base * (.6 + .4 * math.sin(t * math.pi * 2 + i * .8));
      final hh = gap * 2.4 * amp;
      final x = center.dx - width / 2 + gap * (i + .5);
      c.drawLine(Offset(x, center.dy - hh), Offset(x, center.dy + hh), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.t != t || old.scene != scene;
}
