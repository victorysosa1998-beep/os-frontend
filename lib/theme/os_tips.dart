import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'os_buttons.dart';
import 'os_cartoon.dart';

/// Which tab a tip's button should jump to (null = just close).
enum OsTipTarget { feed, discover, chats, features, you }

class OsTip {
  final String id;
  final CartoonScene scene;
  final String eyebrow;
  final String title;
  final String body;
  final String cta;
  final IconData ctaIcon;
  final OsTipTarget? target;
  final List<IconData> chips;
  const OsTip({
    required this.id,
    required this.scene,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.cta,
    required this.ctaIcon,
    this.target,
    this.chips = const [],
  });
}

enum OsTipResult { cta, later, turnOff }

/// Decides WHEN a tip is due and remembers progress. It never shows UI by
/// itself; the app shell asks it and then calls [showOsTipPopup].
class OsTipService {
  static const _lastKey = 'os_tip_last_shown_ms';
  static const _nextKey = 'os_tip_next_index';
  static const _offKey = 'os_tips_disabled';
  static const _tourKey = 'os_feature_tour_seen_v1';

  /// Minimum gap between two tips (also across app launches).
  static const Duration cooldown = Duration(minutes: 25);

  static const List<OsTip> tips = [
    OsTip(
      id: 'verified',
      scene: CartoonScene.verified,
      eyebrow: 'TRUST FIRST',
      title: 'Get your verified badge',
      body: 'Verified members get chat and calls unlocked, and everyone can see you are the real deal.',
      cta: 'Open features',
      ctaIcon: Icons.verified_rounded,
      target: OsTipTarget.features,
      chips: [Icons.verified_rounded, Icons.lock_open_rounded, Icons.star_rounded],
    ),
    OsTip(
      id: 'discover',
      scene: CartoonScene.discover,
      eyebrow: 'DISCOVER',
      title: 'Find people near you',
      body: 'Tap "Find people nearby" and slide the distance to meet members around your city.',
      cta: 'Go to Discover',
      ctaIcon: Icons.explore_rounded,
      target: OsTipTarget.discover,
      chips: [Icons.near_me_rounded, Icons.favorite_rounded, Icons.search_rounded],
    ),
    OsTip(
      id: 'voice',
      scene: CartoonScene.voice,
      eyebrow: 'SPEAK UP',
      title: 'Add a voice intro',
      body: 'A short voice note on your profile makes you instantly more memorable than a bio.',
      cta: 'Open my profile',
      ctaIcon: Icons.mic_rounded,
      target: OsTipTarget.you,
      chips: [Icons.mic_rounded, Icons.graphic_eq_rounded, Icons.play_arrow_rounded],
    ),
    OsTip(
      id: 'reply',
      scene: CartoonScene.chat,
      eyebrow: 'CHAT TIP',
      title: 'Swipe a message to reply',
      body: 'Swipe any message sideways to quote it, or press and hold to react and see more actions.',
      cta: 'Open chats',
      ctaIcon: Icons.chat_bubble_rounded,
      target: OsTipTarget.chats,
      chips: [Icons.reply_rounded, Icons.emoji_emotions_rounded, Icons.call_rounded],
    ),
    OsTip(
      id: 'status',
      scene: CartoonScene.discover,
      eyebrow: 'SHARE A MOMENT',
      title: 'Post a status',
      body: 'Share a photo, a video or a voice status. It is the easiest way to start conversations.',
      cta: 'Go to Feed',
      ctaIcon: Icons.add_a_photo_rounded,
      target: OsTipTarget.feed,
      chips: [Icons.image_rounded, Icons.videocam_rounded, Icons.mic_rounded],
    ),
    OsTip(
      id: 'privacy',
      scene: CartoonScene.safety,
      eyebrow: 'YOU ARE IN CONTROL',
      title: 'Your photo, your rules',
      body: 'Hide your profile photo and approve who gets to see it. You can change this any time.',
      cta: 'Open my profile',
      ctaIcon: Icons.visibility_off_rounded,
      target: OsTipTarget.you,
      chips: [Icons.lock_rounded, Icons.visibility_rounded, Icons.shield_rounded],
    ),
    OsTip(
      id: 'calls',
      scene: CartoonScene.voice,
      eyebrow: 'FACE TO FACE',
      title: 'Voice and video calls',
      body: 'Once you are connected you can call right from the chat. Check Features for more tools.',
      cta: 'See features',
      ctaIcon: Icons.videocam_rounded,
      target: OsTipTarget.features,
      chips: [Icons.call_rounded, Icons.videocam_rounded, Icons.headset_mic_rounded],
    ),
    OsTip(
      id: 'safety',
      scene: CartoonScene.safety,
      eyebrow: 'STAY SAFE',
      title: 'Block and report anytime',
      body: 'Never send money to someone you only met online. Use block or report on any profile.',
      cta: 'Got it',
      ctaIcon: Icons.health_and_safety_rounded,
      chips: [Icons.block_rounded, Icons.flag_rounded, Icons.health_and_safety_rounded],
    ),
  ];

  static Future<bool> isDisabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_offKey) ?? false;
  }

  static Future<void> setDisabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_offKey, value);
  }

  /// Returns the tip that should be shown now, or null.
  static Future<OsTip?> nextDue() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_offKey) ?? false) return null;
    // The first-run tour always comes first.
    if (p.getBool(_tourKey) != true) return null;
    final last = p.getInt(_lastKey);
    if (last != null) {
      final gap = DateTime.now().millisecondsSinceEpoch - last;
      if (gap < cooldown.inMilliseconds) return null;
    }
    final i = (p.getInt(_nextKey) ?? 0) % tips.length;
    return tips[i];
  }

  static Future<void> markShown() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_lastKey, DateTime.now().millisecondsSinceEpoch);
    final i = (p.getInt(_nextKey) ?? 0) + 1;
    await p.setInt(_nextKey, i % tips.length);
  }
}

/// Shows the animated tip popup. Resolves with what the person chose.
Future<OsTipResult> showOsTipPopup(BuildContext context, OsTip tip) async {
  final result = await showGeneralDialog<OsTipResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close tip',
    barrierColor: Colors.black.withValues(alpha: .62),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => _OsTipCard(tip: tip),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween<double>(begin: .86, end: 1).animate(curved), child: child),
      );
    },
  );
  return result ?? OsTipResult.later;
}

class _OsTipCard extends StatefulWidget {
  final OsTip tip;
  const _OsTipCard({required this.tip});

  @override
  State<_OsTipCard> createState() => _OsTipCardState();
}

class _OsTipCardState extends State<_OsTipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tip = widget.tip;
    final maxH = MediaQuery.sizeOf(context).height * .88;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Material(
            color: OsColors.surface,
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
              side: BorderSide(color: OsColors.border.withValues(alpha: .9)),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    height: 200,
                    child: Stack(children: [
                      Positioned.fill(
                        child: CartoonSceneView(scene: tip.scene, borderRadius: BorderRadius.zero),
                      ),
                      // Floating feature chips that gently bob.
                      for (var i = 0; i < tip.chips.length; i++)
                        _FloatChip(
                          icon: tip.chips[i],
                          anim: _float,
                          phase: i * .33,
                          left: i == 0 ? 18 : null,
                          right: i == 1 ? 18 : (i == 2 ? 70 : null),
                          top: i == 0 ? 20 : (i == 1 ? 32 : 130),
                        ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: OsIconBtn(
                          icon: Icons.close_rounded,
                          size: 36,
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(context).pop(OsTipResult.later),
                        ),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        tip.eyebrow,
                        style: const TextStyle(
                          color: OsColors.purple,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tip.title,
                        style: const TextStyle(fontSize: 24, height: 1.1, fontWeight: FontWeight.w900, letterSpacing: -.5),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        tip.body,
                        style: const TextStyle(color: OsColors.muted, fontSize: 14, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      OsButton(
                        label: tip.cta,
                        icon: tip.ctaIcon,
                        onPressed: () => Navigator.of(context).pop(OsTipResult.cta),
                      ),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: OsButton(
                            label: 'Maybe later',
                            kind: OsBtnKind.ghost,
                            height: 44,
                            onPressed: () => Navigator.of(context).pop(OsTipResult.later),
                          ),
                        ),
                        Expanded(
                          child: OsButton(
                            label: 'Stop tips',
                            kind: OsBtnKind.ghost,
                            height: 44,
                            onPressed: () => Navigator.of(context).pop(OsTipResult.turnOff),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatChip extends StatelessWidget {
  final IconData icon;
  final Animation<double> anim;
  final double phase;
  final double? left;
  final double? right;
  final double top;
  const _FloatChip({
    required this.icon,
    required this.anim,
    required this.phase,
    required this.top,
    this.left,
    this.right,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      child: AnimatedBuilder(
        animation: anim,
        builder: (_, child) {
          final v = (anim.value + phase) % 1.0;
          return Transform.translate(offset: Offset(0, (v - .5) * 12), child: child);
        },
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .2),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: .35)),
          ),
          child: Icon(icon, color: Colors.white, size: 23),
        ),
      ),
    );
  }
}
