import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/os_cartoon.dart';
import '../theme/os_layout.dart';
import '../theme/os_ui.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  final CartoonScene scene;
  final IconData icon;
  final String title;
  final String body;
  const _Slide(this.scene, this.icon, this.title, this.body);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int index = 0;

  static const _slides = [
    _Slide(
      CartoonScene.verified,
      Icons.verified_user_rounded,
      'Verified profiles only',
      'Every member passes a quick liveness check, so the person you meet is the person in the photo.',
    ),
    _Slide(
      CartoonScene.discover,
      Icons.explore_rounded,
      'Discover people near you',
      'Browse the feed, filter by state or distance, and send a connection request when something clicks.',
    ),
    _Slide(
      CartoonScene.chat,
      Icons.chat_bubble_rounded,
      'Chat once you both agree',
      'Conversations open only after a request is accepted. Block and report are always one tap away.',
    ),
    _Slide(
      CartoonScene.voice,
      Icons.record_voice_over_rounded,
      'Voice dates & date safety',
      'Try a 5-minute blind voice date, call inside the app, and alert trusted friends if you go quiet on a date.',
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void next() {
    if (index == _slides.length - 1) {
      widget.onDone();
    } else {
      _page.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  Widget _art(_Slide s, {required double height}) => Container(
        height: height,
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: OsColors.purpleDeep.withValues(alpha: .32), blurRadius: 34, offset: const Offset(0, 16)),
          ],
        ),
        child: Stack(fit: StackFit.expand, children: [
          CartoonSceneView(scene: s.scene),
          Positioned(
            left: 14,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .38),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s.icon, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                const Text('REAL PEOPLE · REAL CONNECTIONS',
                    style: TextStyle(color: Colors.white, fontSize: 9.5, letterSpacing: 1, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ]),
      );

  Widget _text(_Slide s, {required TextAlign align}) => Column(
        crossAxisAlignment: align == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.title,
              textAlign: align,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.6, height: 1.15)),
          const SizedBox(height: 14),
          Text(s.body, textAlign: align, style: const TextStyle(color: OsColors.muted, fontSize: 15, height: 1.5)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final last = index == _slides.length - 1;
    return Scaffold(
      body: OsBackground(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final landscape = c.maxWidth > c.maxHeight && c.maxWidth >= 640;
            final artHeight = landscape ? c.maxHeight * .62 : (c.maxHeight < 640 ? 210.0 : (c.maxHeight < 760 ? 250.0 : 300.0));
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const OsLogo(size: 36),
                  AnimatedOpacity(
                    opacity: last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(onPressed: last ? null : widget.onDone, child: const Text('Skip')),
                  ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => index = i),
                  itemBuilder: (_, i) {
                    final s = _slides[i];
                    if (landscape) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Row(children: [
                          Expanded(child: Center(child: _art(s, height: artHeight))),
                          const SizedBox(width: 36),
                          Expanded(child: Center(child: SingleChildScrollView(child: _text(s, align: TextAlign.start)))),
                        ]),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: c.maxHeight - 190),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Center(child: _art(s, height: artHeight)),
                              SizedBox(height: c.maxHeight < 700 ? 28 : 40),
                              _text(s, align: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == index ? 26 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == index ? OsColors.purple : OsColors.border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                child: ResponsiveBody(
                  maxWidth: 420,
                  child: OsGradientButton(
                    label: last ? 'Get started' : 'Next',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: next,
                  ),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}
