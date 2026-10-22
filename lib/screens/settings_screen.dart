import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/os_dialogs.dart';
import '../theme/os_layout.dart';
import '../theme/os_tips.dart';
import '../theme/os_ui.dart';
import '../theme/user_badge.dart';
import 'Extras_screens.dart';
import 'dating_features_screen.dart';
import 'verification_screen.dart';

/// Account & app settings. Every feature is also reachable from the Features
/// tab, so Settings is now only for account-level actions plus shortcuts.
class SettingsScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  final VoidCallback? onExploreFeatures;
  const SettingsScreen({super.key, required this.user, required this.onLogout, this.onExploreFeatures});

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await osConfirm(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to see your chats.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
      danger: true,
    );
    if (ok && context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      onLogout();
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final password = await showOsPopup<String>(context, builder: (_) => const _DeleteAccountDialog());
    if (password == null || password.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Api.deleteAccount(password);
      await Api.logout();
      if (!context.mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      onLogout();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete account. ${Api.friendlyError(e)}')));
    }
  }

  void _doc(BuildContext context, String title, List<(String, String)> sections) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => OsInfoPage(title: title, sections: sections)));
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final admin = isAdminUser(user);
    final verified = isVerifiedUser(user);
    final statusColor = admin ? kAdminGold : (verified ? kVerifiedBlue : OsColors.amber);
    final name = (user['display_name'] ?? 'You').toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ResponsiveBody(
          child: ListView(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 28 + MediaQuery.of(context).viewPadding.bottom),
            children: [
              OsCard(
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: OsColors.purpleDeep,
                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      Text((user['email'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: OsColors.muted, fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(verified ? Icons.verified : Icons.shield_outlined, size: 15, color: statusColor),
                        const SizedBox(width: 5),
                        Text(admin ? 'OS Support' : (verified ? 'Verified' : 'Not verified yet'),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: statusColor)),
                      ]),
                    ]),
                  ),
                ]),
              ),
              const _Label('Features (also in the Features tab)'),
              _Tile(Icons.auto_awesome_rounded, 'Explore OS features', () {
                if (onExploreFeatures != null) {
                  onExploreFeatures!();
                } else {
                  _doc(context, 'Explore OS features', const [
                    ('Real people', 'OS is designed around identity-first connections and respectful interactions.'),
                    ('Privacy controls', 'Manage discovery visibility, contact sharing and photo reveal requests.'),
                    ('Chat and calls', 'Reply to messages, react, and connect when you are ready.'),
                    ('Safety tools', 'Block or report accounts and review the community guidelines.'),
                  ]);
                }
              }),
              const _TipsSwitch(),
              _Tile(Icons.tune_rounded, 'Dating preferences & privacy',
                  () => _push(context, const OsDatingFeaturesScreen())),
              _Tile(Icons.visibility_outlined, 'Photo reveal requests',
                  () => _push(context, const PhotoRevealRequestsScreen())),
              if (!admin)
                _Tile(
                  Icons.verified_user_outlined,
                  'Identity verification',
                  () => _push(
                    context,
                    Scaffold(
                      appBar: AppBar(title: const Text('Identity verification')),
                      body: SafeArea(child: VerificationScreen(user: user, onChanged: (_) {})),
                    ),
                  ),
                ),
              _Tile(Icons.record_voice_over_rounded, 'Blind voice date', () => _push(context, BlindDateScreen(user: user))),
              _Tile(Icons.health_and_safety_rounded, 'Date safety kit', () => _push(context, const SafetyKitScreen())),
              const _Label('Safety'),
              _Tile(Icons.health_and_safety_outlined, 'Safety tips', () => _doc(context, 'Safety tips', OsInfoContent.safety)),
              _Tile(Icons.rule_rounded, 'Community guidelines',
                  () => _doc(context, 'Community guidelines', OsInfoContent.guidelines)),
              _Tile(Icons.shield_outlined, 'Child safety standards', () async {
                final uri = Uri.parse('${Api.baseUrl}/child-safety');
                final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the child safety page. Please try again.')));
              }),
              const _Label('Legal'),
              _Tile(Icons.lock_outline, 'Privacy Policy', () async {
                final opened = await launchUrl(Uri.parse('${Api.baseUrl}/privacy-policy'), mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the Privacy Policy. Please try again.')));
              }),
              _Tile(Icons.description_outlined, 'Terms of Service', () async {
                final opened = await launchUrl(Uri.parse('${Api.baseUrl}/terms'), mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the Terms of Service. Please try again.')));
              }),
              const _Label('About'),
              _Tile(Icons.info_outline, 'About OS', () {
                showAboutDialog(
                  context: context,
                  applicationName: 'OS — Real Connections',
                  applicationVersion: '1.0.0',
                  applicationLegalese: 'Built with immense love ❤️',
                );
              }),
              if (!admin) ...[
                const _Label('Account'),
                _Tile(Icons.delete_outline_rounded, 'Delete account', () => _deleteAccount(context), color: Colors.red),
                _Tile(Icons.open_in_browser, 'Account deletion help (web)', () async {
                  final opened = await launchUrl(Uri.parse('${Api.baseUrl}/account-deletion'), mode: LaunchMode.externalApplication);
                  if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open account deletion help. Please try again.')));
                }),
              ],
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded, color: OsColors.coral),
                label: const Text('Sign out', style: TextStyle(color: OsColors.coral)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: OsColors.coral)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared copy for the info pages (used by Settings and the Features hub).
class OsInfoContent {
  static const safety = [
    ('Keep it on the app', 'Stay in OS chat until you trust someone. Never share financial details, passwords or codes.'),
    ('Meet safely', 'Meet in a public place, tell a friend where you are going and arrange your own transport.'),
    ('Trust your instincts', 'If something feels off, block and report. Our moderators review every report.'),
  ];
  static const guidelines = [
    ('Be real', 'Use your own photos and identity. Fake profiles are removed.'),
    ('Be respectful', 'No harassment, hate, threats or unwanted explicit content.'),
    ('18+ only', 'OS is strictly for adults. Under-18 users are not permitted; accounts found to belong to minors are restricted and reviewed for removal.'),
    ('Consent matters', 'Respect a no. Repeated unwanted contact leads to suspension.'),
  ];
  static const privacy = [
    ('Verification media', 'Your liveness video and comparison photo are used only to confirm you are real and are reviewed privately by authorized moderators.'),
    ('Your profile photo', 'You can hide your profile photo anytime from the You tab.'),
    ('Location', 'Location is used only to show distance to others when you choose Nearby.'),
  ];
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 0, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(color: OsColors.muted, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800)),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;
  const _Tile(this.icon, this.title, this.onTap, {this.color});
  @override
  Widget build(BuildContext context) => OsCard(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: color ?? OsColors.purple),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color))),
          const Icon(Icons.chevron_right, color: OsColors.muted),
        ]),
      );
}

class OsInfoPage extends StatelessWidget {
  final String title;
  final List<(String, String)> sections;
  const OsInfoPage({super.key, required this.title, required this.sections});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ResponsiveBody(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final s in sections)
                  OsCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.$1, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(s.$2, style: const TextStyle(color: OsColors.muted, height: 1.5)),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// Owns its text controller so it is disposed only when the dialog route
/// is really gone (not while the close animation is still running).
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OsPopup(
        icon: Icons.delete_forever_rounded,
        title: 'Permanently delete your account?',
        message: 'This deletes your profile, posts, conversations and associated app records. This cannot be undone.',
        colors: const [Color(0xFFB4233C), Color(0xFFFF6B7A)],
        body: TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm your password', prefixIcon: Icon(Icons.lock_outline)),
        ),
        actions: [
          const OsPopupAction('Cancel'),
          OsPopupAction('Delete account', kind: OsActionKind.danger, resultBuilder: () => _password.text),
        ],
      );
}

class PhotoRevealRequestsScreen extends StatefulWidget {
  const PhotoRevealRequestsScreen({super.key});
  @override
  State<PhotoRevealRequestsScreen> createState() => _PhotoRevealRequestsScreenState();
}

class _PhotoRevealRequestsScreenState extends State<PhotoRevealRequestsScreen> {
  bool loading = true;
  List<dynamic> requests = [];
  final Set<int> deciding = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await Api.photoRevealRequests();
      if (!mounted) return;
      setState(() {
        requests = data;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not load requests. ${Api.friendlyError(e)}')));
    }
  }

  Future<void> _decide(int id, String decision) async {
    if (deciding.contains(id)) return;
    setState(() => deciding.add(id));
    try {
      await Api.decidePhotoReveal(id, decision);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(decision == 'approved' ? 'Photo reveal approved.' : 'Request declined.')));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e))));
    } finally {
      if (mounted) setState(() => deciding.remove(id));
    }
  }

  Widget _empty() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 60),
          Icon(Icons.visibility_off_outlined, size: 64, color: OsColors.muted),
          SizedBox(height: 16),
          Text('No pending photo requests',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text(
            'When someone asks to see your protected photo, you can approve or decline it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: OsColors.muted, height: 1.5),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Photo reveal requests')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ResponsiveBody(
                  child: requests.isEmpty
                      ? _empty()
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: requests.length,
                          itemBuilder: (context, index) {
                            final item = Map<String, dynamic>.from(requests[index] as Map);
                            final person = item['requester'] is Map
                                ? Map<String, dynamic>.from(item['requester'])
                                : <String, dynamic>{};
                            final id = int.tryParse('${item['id']}') ?? 0;
                            final busy = deciding.contains(id);
                            final name = '${person['display_name'] ?? 'OS member'}';
                            return OsCard(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: OsColors.purpleDeep,
                                    child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.w900)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                                      const Text('wants to see your protected photo',
                                          style: TextStyle(color: OsColors.muted, fontSize: 12.5)),
                                    ]),
                                  ),
                                ]),
                                const SizedBox(height: 14),
                                Row(children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: busy ? null : () => _decide(id, 'rejected'),
                                      child: const Text('Decline'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: busy ? null : () => _decide(id, 'approved'),
                                      child: busy
                                          ? const SizedBox(
                                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Text('Approve'),
                                    ),
                                  ),
                                ]),
                              ]),
                            );
                          }),
                ),
              ),
      );
}

/// Turns the regular feature pop-ups on or off.
class _TipsSwitch extends StatefulWidget {
  const _TipsSwitch();

  @override
  State<_TipsSwitch> createState() => _TipsSwitchState();
}

class _TipsSwitchState extends State<_TipsSwitch> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    OsTipService.isDisabled().then((off) {
      if (mounted) setState(() => _on = !off);
    });
  }

  @override
  Widget build(BuildContext context) {
    return OsCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        secondary: const Icon(Icons.lightbulb_rounded, color: OsColors.amber),
        title: const Text('Feature tips', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        subtitle: const Text('A friendly pop-up now and then about what OS can do',
            style: TextStyle(color: OsColors.muted, fontSize: 12)),
        value: _on,
        onChanged: (v) {
          setState(() => _on = v);
          OsTipService.setDisabled(!v);
        },
      ),
    );
  }
}
