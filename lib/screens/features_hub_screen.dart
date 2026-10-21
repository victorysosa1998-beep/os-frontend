import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/os_cartoon.dart';
import '../theme/os_layout.dart';
import '../theme/user_badge.dart';
import 'Extras_screens.dart';
import 'dating_features_screen.dart';
import 'settings_screen.dart';
import 'verification_screen.dart';

/// A top-level tab that puts every OS feature one tap away. Nothing important
/// lives only inside Settings any more.
class FeaturesHub extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onShowTour;
  final VoidCallback onLogout;
  final void Function(Map<String, dynamic> user) onUserChanged;

  const FeaturesHub({
    super.key,
    required this.user,
    required this.onShowTour,
    required this.onLogout,
    required this.onUserChanged,
  });

  @override
  State<FeaturesHub> createState() => _FeaturesHubState();
}

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;
  final int badge;
  const _Feature(this.icon, this.title, this.subtitle, this.colors, this.onTap, {this.badge = 0});
}

class _FeaturesHubState extends State<FeaturesHub> {
  int pendingReveals = 0;

  bool get admin => isAdminUser(widget.user);
  bool get verified => isVerifiedUser(widget.user);

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    try {
      final rows = await Api.photoRevealRequests();
      if (mounted) setState(() => pendingReveals = rows.length);
    } catch (_) {
      // Badges are optional; the hub keeps working offline.
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    _loadBadges();
  }

  void _openVerification() => _open(Scaffold(
        appBar: AppBar(title: const Text('Identity verification')),
        body: SafeArea(
          child: VerificationScreen(user: widget.user, onChanged: widget.onUserChanged),
        ),
      ));

  void _openSettings() => _open(SettingsScreen(
        user: widget.user,
        onLogout: widget.onLogout,
        onExploreFeatures: widget.onShowTour,
      ));

  List<_Feature> get _connect => [
        _Feature(Icons.record_voice_over_rounded, 'Blind voice date', '5 minutes, voices only',
            const [Color(0xFFB04CD9), Color(0xFFFF6B7A)], () => _open(BlindDateScreen(user: widget.user))),
        _Feature(Icons.mic_rounded, 'Voice status', 'Share a short voice note',
            const [Color(0xFF7C3AED), Color(0xFF9B7BFF)], () => _open(const VoiceStatusScreen())),
        _Feature(Icons.tune_rounded, 'Dating preferences', 'Discovery, distance & icebreakers',
            const [Color(0xFF5B34C9), Color(0xFF8B5CF6)], () => _open(const OsDatingFeaturesScreen())),
      ];

  List<_Feature> get _trust => [
        _Feature(Icons.visibility_rounded, 'Photo requests', 'Approve who can see your photo',
            const [Color(0xFFFF6B7A), Color(0xFFFFA06B)], () => _open(const PhotoRevealRequestsScreen()),
            badge: pendingReveals),
        if (!admin)
          _Feature(
              verified ? Icons.verified_rounded : Icons.verified_user_outlined,
              verified ? 'Verified' : 'Verify identity',
              verified ? 'Your identity is confirmed' : 'Unlock chat & calls',
              const [Color(0xFF1DA1F2), Color(0xFF6B8CFF)],
              _openVerification),
        _Feature(Icons.health_and_safety_rounded, 'Date safety kit', 'Alert friends if you go quiet',
            const [Color(0xFF1F9D8B), Color(0xFF5BD6A8)], () => _open(const SafetyKitScreen())),
        _Feature(Icons.shield_outlined, 'Safety tips', 'Meet and chat safely',
            const [Color(0xFF3B82F6), Color(0xFF7C9CFF)],
            () => _open(OsInfoPage(title: 'Safety tips', sections: OsInfoContent.safety))),
      ];

  List<_Feature> get _help => [
        _Feature(Icons.auto_awesome_rounded, 'App tour', 'See what OS can do', const [Color(0xFFF5B400), Color(0xFFFF9A3D)],
            widget.onShowTour),
        _Feature(Icons.rule_rounded, 'Community rules', 'How we keep OS respectful',
            const [Color(0xFF8B5CF6), Color(0xFFB04CD9)],
            () => _open(OsInfoPage(title: 'Community guidelines', sections: OsInfoContent.guidelines))),
        _Feature(Icons.lock_outline_rounded, 'Privacy', 'How your data is used',
            const [Color(0xFF475569), Color(0xFF94A3B8)],
            () => _open(OsInfoPage(title: 'Privacy', sections: OsInfoContent.privacy))),
        _Feature(Icons.settings_rounded, 'Settings & account', 'Sign out, delete account',
            const [Color(0xFF334155), Color(0xFF64748B)], _openSettings),
      ];

  Widget _section(String label, List<_Feature> items) => SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    color: OsColors.muted, fontSize: 11.5, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
          ),
        ),
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisExtent: 132,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate((_, i) => _tile(items[i]), childCount: items.length),
        ),
      ]);

  Widget _tile(_Feature f) => Material(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: f.onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: OsColors.border.withValues(alpha: .8)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(colors: f.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: Icon(f.icon, color: Colors.white, size: 24),
                ),
                const Spacer(),
                if (f.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: OsColors.coral, borderRadius: BorderRadius.circular(12)),
                    child: Text('${f.badge}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                  )
                else
                  const Icon(Icons.chevron_right_rounded, color: OsColors.muted),
              ]),
              const Spacer(),
              Text(f.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 2),
              Text(f.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: OsColors.muted, fontSize: 12, height: 1.3)),
            ]),
          ),
        ),
      );

  Widget _hero() => SizedBox(
        height: 168,
        child: Stack(fit: StackFit.expand, children: [
          const CartoonSceneView(scene: CartoonScene.discover, borderRadius: BorderRadius.all(Radius.circular(26))),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              const Text('Your OS toolkit',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(admin ? 'Support & safety tools' : 'Everything you need, one tap away',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
        ]),
      );

  Widget _verifyBanner() => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: OsColors.coral.withValues(alpha: .12),
          border: Border.all(color: OsColors.coral.withValues(alpha: .5)),
        ),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: OsColors.coral, size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Get verified', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              SizedBox(height: 2),
              Text('A 30-second liveness check unlocks chat and calls.',
                  style: TextStyle(color: OsColors.muted, fontSize: 12.5, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _openVerification,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 16)),
            child: const Text('Start'),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadBadges,
      child: ResponsiveBody(
        maxWidth: 900,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              sliver: SliverMainAxisGroup(slivers: [
                SliverToBoxAdapter(child: _hero()),
                if (!verified && !admin) SliverToBoxAdapter(child: _verifyBanner()),
                _section('Connect & date', _connect),
                _section('Privacy & trust', _trust),
                _section('Help & account', _help),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
