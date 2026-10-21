import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';

/// Welcome → Splash sequence. Calls [onFinished] once both the animation
/// and [ready] (e.g. session check) are complete.
class IntroSequence extends StatefulWidget {
  final Future<void> ready;
  final VoidCallback onFinished;
  const IntroSequence({super.key, required this.ready, required this.onFinished});

  @override
  State<IntroSequence> createState() => _IntroSequenceState();
}

class _IntroSequenceState extends State<IntroSequence> {
  bool splash = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => splash = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 900),
      child: splash
          ? SplashScreen(
              key: const ValueKey('splash'),
              ready: widget.ready,
              onFinished: widget.onFinished,
            )
          : const WelcomeScreen(key: ValueKey('welcome')),
    );
  }
}

// ----------------- WELCOME SCREEN -----------------
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..forward();
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
    _scale = Tween<double>(begin: 0.85, end: 1.05)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OsColors.bg,
      body: OsBackground(
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const OsLogo(size: 72, showWordmark: false),
                  const SizedBox(height: 26),
                  Text('WELCOME',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .92),
                        fontSize: 34,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 10,
                      )),
                  const SizedBox(height: 14),
                  Container(
                    width: 56,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: OsColors.brandGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------- SPLASH SCREEN -----------------
class SplashScreen extends StatefulWidget {
  final Future<void> ready;
  final VoidCallback onFinished;
  const SplashScreen({super.key, required this.ready, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.12)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));
    _opacity = Tween<double>(begin: 0.65, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

    // Wait for the minimum splash time AND the session check.
    Future.wait([
      Future<void>.delayed(const Duration(seconds: 3)),
      widget.ready,
    ]).whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OsColors.bg,
      body: OsBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _scale,
                        child: FadeTransition(
                          opacity: _opacity,
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: OsColors.purple.withValues(alpha: .35),
                                  blurRadius: 50,
                                  spreadRadius: 8,
                                ),
                              ],
                            ),
                            child: const OsLogo(size: 92, showWordmark: false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('os',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 5)),
                      const SizedBox(height: 10),
                      const Text('Real people. Real connections.',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 15, letterSpacing: 1.1)),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(seconds: 3),
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: .08),
                      valueColor: const AlwaysStoppedAnimation(OsColors.purple),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('Built with immense love ❤️',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .6),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
