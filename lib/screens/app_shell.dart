import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:os_dating/screens/Extras_screens.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import '../services/push_notification_service.dart';

import '../data/nigerian_states.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';
import '../theme/os_dialogs.dart';
import '../theme/os_layout.dart';
import '../theme/os_cartoon.dart';
import '../theme/os_buttons.dart';
import '../theme/os_chrome.dart';
import '../theme/os_tips.dart';
import 'features_hub_screen.dart';
import '../theme/user_badge.dart';
import 'chat_screen.dart';
import 'call_screen.dart';
import 'settings_screen.dart';
import 'verification_screen.dart';
import 'admin_screen.dart';

export '../theme/user_badge.dart'
    show kVerifiedBlue, kAdminGold, isAdminUser, isVerifiedUser, UserBadge;

/// Id of the signed-in user, set by AppShell.
String currentUserId = '';
bool currentUserIsAdmin = false;

String _idText(dynamic v) {
  final t = v == null ? '' : '$v'.trim();
  return t == 'null' ? '' : t;
}

/// True when a feed post or discover entry belongs to the signed-in user.
/// Checks every shape the backend may use (flat user, {user: {...}},
/// {author: {...}}, *_id fields) and falls back to the e-mail address.
/// Set [idIsUser] when [item] is itself a user record (its `id` is a user id).
bool _belongsToCurrentUser(Map item, Map<String, dynamic> user,
    {bool idIsUser = false}) {
  var mine = _idText(user['id']);
  if (mine.isEmpty) mine = currentUserId.trim();
  final myEmail = _idText(user['email']).toLowerCase();

  final records = <Map>[item];
  for (final key in const ['user', 'profile', 'member', 'author', 'owner']) {
    final v = item[key];
    if (v is Map) records.add(v);
  }

  for (final r in records) {
    final isNested = !identical(r, item);
    final ids = <dynamic>[
      r['user_id'],
      r['author_id'],
      r['owner_id'],
      r['poster_id'],
      if (isNested || idIsUser) r['id'],
    ];
    if (mine.isNotEmpty && ids.any((v) => _idText(v) == mine)) return true;
    final email = _idText(r['email']).toLowerCase();
    if (myEmail.isNotEmpty && email == myEmail) return true;
  }
  return false;
}

// ============================================================
// APP SHELL
// ============================================================

class AppShell extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  const AppShell({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  State<AppShell> createState() => _ShellState();
}

class _ShellState extends State<AppShell> {
  int tab = 0;
  late Map<String, dynamic> user;
  Timer? _incomingCallTimer;
  Timer? _photoRevealTimer;
  bool _showingIncomingCall = false;
  bool _showingRevealPopup = false;
  bool _showingFeatureTour = false;
  bool _showingTip = false;
  Timer? _tipTimer;
  int _pendingReveals = 0;
  final Set<int> _handledIncomingCalls = <int>{};
  final Set<int> _handledRevealRequests = <int>{};

  bool get isVerified => isVerifiedUser(user);
  bool get isAdmin => isAdminUser(user);
  bool get needsVerification => !isVerified && !isAdmin;

  @override
  void initState() {
    super.initState();
    user = Map<String, dynamic>.from(widget.user);
    currentUserId = '${user['id'] ?? ''}';
    currentUserIsAdmin = isAdminUser(user);
    _photoRevealTimer = Timer.periodic(const Duration(seconds: 12), (_) => _pollRevealRequests());
    Future<void>.delayed(const Duration(seconds: 2), _maybeShowFeatureTour);
    _tipTimer = Timer.periodic(const Duration(seconds: 45), (_) => _maybeShowTip());
    _incomingCallTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _pollIncomingCalls());
    Future<void>.delayed(const Duration(milliseconds: 700), _pollIncomingCalls);
  }

  @override
  void dispose() {
    _incomingCallTimer?.cancel();
    _photoRevealTimer?.cancel();
    _tipTimer?.cancel();
    super.dispose();
  }

  Future<void> _maybeShowFeatureTour() async {
    if (!mounted || isAdmin || _showingFeatureTour || _showingIncomingCall) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('os_feature_tour_seen_v1') == true || !mounted) return;
    _showingFeatureTour = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _OsFeatureTourDialog(),
    );
    _showingFeatureTour = false;
    await prefs.setBool('os_feature_tour_seen_v1', true);
  }

  /// Regular, friendly feature pop-up. Only appears when nothing else is on
  /// screen (no call, reveal popup, tour or other page above the tabs).
  Future<void> _maybeShowTip() async {
    if (!mounted || isAdmin || _showingTip) return;
    if (_showingIncomingCall || _showingRevealPopup || _showingFeatureTour) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final tip = await OsTipService.nextDue();
    if (tip == null || !mounted) return;
    _showingTip = true;
    final result = await showOsTipPopup(context, tip);
    _showingTip = false;
    await OsTipService.markShown();
    if (result == OsTipResult.turnOff) {
      await OsTipService.setDisabled(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tips turned off. You can turn them on again in Settings.')),
        );
      }
    } else if (result == OsTipResult.cta && tip.target != null && mounted) {
      setState(() => tab = tip.target!.index);
    }
  }

  Future<void> _showFeatureTourNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('os_feature_tour_seen_v1');
    await _maybeShowFeatureTour();
  }

  Future<void> _pollRevealRequests() async {
    if (!mounted || isAdmin) return;
    try {
      final rows = await Api.photoRevealRequests();
      if (!mounted) return;
      if (rows.length != _pendingReveals) setState(() => _pendingReveals = rows.length);
      if (_showingIncomingCall || _showingRevealPopup || _showingFeatureTour) return;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = int.tryParse('${item['id'] ?? ''}');
        if (id == null || _handledRevealRequests.contains(id)) continue;
        _handledRevealRequests.add(id);
        final requester = item['requester'] is Map ? Map<String, dynamic>.from(item['requester']) : <String, dynamic>{};
        final name = '${requester['display_name'] ?? 'An OS member'}';
        _showingRevealPopup = true;
        final review = await showOsPopup<bool>(
          context,
          builder: (_) => OsPopup(
            icon: Icons.visibility_rounded,
            title: 'Someone wants to see your photo',
            message: '$name requested a photo reveal. You decide whether to approve.',
            actions: const [
              OsPopupAction('Later', result: false),
              OsPopupAction('Review', icon: Icons.arrow_forward_rounded, kind: OsActionKind.primary, result: true),
            ],
          ),
        );
        _showingRevealPopup = false;
        if (review == true && mounted) {
          await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PhotoRevealRequestsScreen()));
          unawaited(_pollRevealRequests());
        }
        return;
      }
    } catch (_) {
      // Keep normal app navigation responsive while offline.
    }
  }

  Future<void> _pollIncomingCalls() async {
    if (!mounted || _showingIncomingCall) return;
    try {
      final calls = await Api.incomingCalls();
      if (!mounted || _showingIncomingCall) return;
      for (final raw in calls) {
        if (raw is! Map) continue;
        final call = Map<String, dynamic>.from(raw);
        final id = int.tryParse('${call['id'] ?? ''}');
        if (id == null || _handledIncomingCalls.contains(id)) continue;
        final listedStatus = '${call['status'] ?? 'ringing'}';
        if (listedStatus != 'ringing') continue;
        _handledIncomingCalls.add(id);
        _showingIncomingCall = true;
        final other = call['other_user'] is Map
            ? Map<String, dynamic>.from(call['other_user'])
            : <String, dynamic>{};
        final name = (other['display_name'] ?? 'OS member').toString();
        final video = call['call_type'] == 'video';
        // Close the dialog by itself if the caller hangs up, the call is
        // missed, or it is answered elsewhere while the dialog is open.
        BuildContext? dialogCtx;
        var cancelledByCaller = false;
        var watching = false;
        final watcher = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
          if (watching) return;
          watching = true;
          try {
            final latest = await Api.callStatus(id);
            final st = '${latest['status'] ?? ''}';
            if (st.isNotEmpty && st != 'ringing') {
              cancelledByCaller = true;
              final dc = dialogCtx;
              if (dc != null && dc.mounted) Navigator.of(dc).pop();
            }
          } catch (_) {
            // Offline blips: keep the dialog and try again.
          } finally {
            watching = false;
          }
        });
        // Ring (looping system ringtone) for as long as the popup is open.
        try { FlutterRingtonePlayer().playRingtone(looping: true, volume: 1.0, asAlarm: false); } catch (_) {}
        final answer = await showIncomingCallPopup(
          context,
          name: name,
          video: video,
          avatar: AvatarPhoto(user: other, radius: 62),
          onBuilt: (ctx) => dialogCtx = ctx,
        );
        watcher.cancel();
        try { FlutterRingtonePlayer().stop(); } catch (_) {}
        // Whatever happened, the 'Incoming call' notification must not linger.
        unawaited(PushNotificationService.clearCallNotification(id));
        try {
          if (cancelledByCaller || answer == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Missed call from $name.')),
              );
            }
          } else if (answer == true) {
            final accepted = await Api.acceptCall(id);
            if (!mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LiveCallScreen(call: accepted, isCaller: false),
              ),
            );
          } else {
            await Api.declineCall(id);
          }
        } catch (_) {
          // Caller may have cancelled while the dialog was open.
        } finally {
          _showingIncomingCall = false;
        }
        return;
      }
    } catch (_) {
      // Incoming call polling is best-effort and must not interrupt normal use.
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      applyUser(widget.user);
    }
  }

  /// Applies a new user map (e.g. after verification status changes).
  void applyUser(Map<String, dynamic> updatedUser) {
    user = Map<String, dynamic>.from(updatedUser);
    currentUserId = '${user['id'] ?? ''}';
    currentUserIsAdmin = isAdminUser(user);
  }

  void refresh(Map<String, dynamic> updatedUser) {
    if (!mounted) return;
    setState(() => applyUser(updatedUser));
  }

  void _openVerification() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Identity verification')),
          body: SafeArea(child: VerificationScreen(user: user, onChanged: refresh)),
        ),
      ),
    );
  }

  void _openSettings() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            user: user,
            onLogout: widget.onLogout,
            onExploreFeatures: _showFeatureTourNow,
          ),
        ),
      );

  Widget _verifyBanner() => Material(
        color: OsColors.coral.withValues(alpha: .14),
        child: InkWell(
          onTap: _openVerification,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(children: [
              const Icon(Icons.shield_outlined, size: 20, color: OsColors.coral),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Verify your identity to unlock chat and calls',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              Text('Verify', style: TextStyle(color: OsColors.coral, fontWeight: FontWeight.w900, fontSize: 13)),
              const Icon(Icons.chevron_right_rounded, color: OsColors.coral, size: 20),
            ]),
          ),
        ),
      );

  Widget _featuresIcon({required bool selected}) => Badge(
        isLabelVisible: _pendingReveals > 0,
        label: Text('$_pendingReveals'),
        backgroundColor: OsColors.coral,
        child: Icon(selected ? Icons.apps_rounded : Icons.apps_outlined),
      );

  @override
  Widget build(BuildContext context) {
    // Admin accounts use a dedicated screen: no Discover tab and no member
    // profile/delete-account controls, even if AppShell is reached directly.
    if (isAdmin) {
      return AdminScreen(user: user, onLogout: widget.onLogout);
    }

    // Tabs: Feed Â· Discover Â· Chats Â· Features Â· You. Features is a first-class
    // tab, so nothing important is hidden inside Settings any more.
    final pages = <Widget>[
      Feed(key: const PageStorageKey('feed'), user: user, onGoTab: (i) => setState(() => tab = i)),
      Discover(key: const PageStorageKey('discover'), user: user),
      Chats(key: const PageStorageKey('chats'), myId: user['id']),
      FeaturesHub(
        key: const PageStorageKey('features'),
        user: user,
        onShowTour: _showFeatureTourNow,
        onLogout: widget.onLogout,
        onUserChanged: refresh,
      ),
      Profile(
        key: const PageStorageKey('profile'),
        user: user,
        onChanged: refresh,
        onLogout: widget.onLogout,
      ),
    ];
    final selectedTab = tab.clamp(0, pages.length - 1);
    final wide = OsBreakpoints.isWide(context);

    final content = Column(children: [
      if (needsVerification) _verifyBanner(),
      Expanded(child: IndexedStack(index: selectedTab, children: pages)),
    ]);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const OsLogo(size: 34),
        actions: [
          OsIconBtn(
            tooltip: 'Settings',
            icon: Icons.settings_rounded,
            size: 42,
            onPressed: _openSettings,
          ),
          const SizedBox(width: 14),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: selectedTab,
                  onDestinationSelected: (i) => setState(() => tab = i),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: OsColors.surface,
                  destinations: [
                    const NavigationRailDestination(
                        icon: Icon(Icons.dynamic_feed_outlined), selectedIcon: Icon(Icons.dynamic_feed), label: Text('Feed')),
                    const NavigationRailDestination(
                        icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: Text('Discover')),
                    const NavigationRailDestination(
                        icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: Text('Chats')),
                    NavigationRailDestination(
                        icon: _featuresIcon(selected: false),
                        selectedIcon: _featuresIcon(selected: true),
                        label: const Text('Features')),
                    const NavigationRailDestination(
                        icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('You')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ])
            : content,
      ),
      bottomNavigationBar: wide
          ? null
          : OsFloatingNavBar(
              index: selectedTab,
              onChanged: (index) => setState(() => tab = index),
              items: [
                OsNavItem(
                  label: 'Feed',
                  icon: (sel) => Icon(sel ? Icons.dynamic_feed : Icons.dynamic_feed_outlined),
                ),
                OsNavItem(
                  label: 'Discover',
                  icon: (sel) => Icon(sel ? Icons.explore : Icons.explore_outlined),
                ),
                OsNavItem(
                  label: 'Chats',
                  icon: (sel) => Icon(sel ? Icons.chat_bubble : Icons.chat_bubble_outline),
                ),
                OsNavItem(
                  label: 'Features',
                  icon: (sel) => _featuresIcon(selected: sel),
                ),
                OsNavItem(
                  label: 'You',
                  icon: (sel) => Icon(sel ? Icons.person : Icons.person_outline),
                ),
              ],
            ),
    );
  }
}

// ============================================================
// PUBLIC PROFILE NAVIGATION
// ============================================================

Future<void> openPublicProfile(
  BuildContext context,
  dynamic rawUser,
) async {
  final person = mapOf(rawUser);
  final id = int.tryParse('${person['id'] ?? ''}');

  if (id == null || id <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this profile.')),
    );
    return;
  }

  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => PublicProfileScreen(
        userId: id,
        initialUser: person,
      ),
    ),
  );
}

class UserTap extends StatelessWidget {
  final Map<String, dynamic> user;
  final Widget child;

  const UserTap({
    super.key,
    required this.user,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPublicProfile(context, user),
      child: child,
    );
  }
}

// ============================================================
// PUBLIC PROFILE
// ============================================================

class PublicProfileScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> initialUser;

  const PublicProfileScreen({
    super.key,
    required this.userId,
    this.initialUser = const {},
  });

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  late Map<String, dynamic> person;
  List<dynamic> posts = [];
  bool loadingProfile = true;
  bool loadingPosts = true;
  String? profileError;
  String? postsError;

  @override
  void initState() {
    super.initState();
    person = Map<String, dynamic>.from(widget.initialUser);
    loadProfile();
    loadPosts();
  }

  Future<void> loadProfile() async {
    try {
      final result = await Api.userProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        person = Map<String, dynamic>.from(result);
        loadingProfile = false;
        profileError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingProfile = false;
        profileError = '$e';
      });
    }
  }

  Future<void> loadPosts() async {
    try {
      final result = await Api.userPosts(widget.userId);
      if (!mounted) return;
      setState(() {
        posts = result;
        loadingPosts = false;
        postsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingPosts = false;
        postsError = '$e';
      });
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([loadProfile(), loadPosts()]);
  }

  /// Tap the avatar to see the full picture, edge to edge.
  void openPhoto() => showProfilePhoto(context, person);

  Future<void> openChat() async {
    try {
      final result = await Api.openConversation(widget.userId);
      final conversationId = int.tryParse(
        '${result['id'] ?? result['conversation_id'] ?? ''}',
      );
      if (conversationId == null) {
        throw Exception('The server did not return a conversation ID.');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            person: person,
            myId: int.tryParse(currentUserId),
            profileBuilder: (id, profile) => PublicProfileScreen(
              userId: id,
              initialUser: profile,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat. ${Api.friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = safeName(person['display_name']);
    final admin = isAdminUser(person);
    final verified = isVerifiedUser(person);
    final city = '${person['city'] ?? ''}'.trim();
    final bio = '${person['bio'] ?? ''}'.trim();
    final phone = '${person['phone_number'] ?? ''}'.trim();
    final online = isOnline(person);

    Widget infoRow({required IconData icon, required String title, required String value}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: OsColors.muted, size: 22),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: OsColors.muted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 15, height: 1.35)),
          ])),
        ]),
      );
    }

    Widget sectionCard({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: OsColors.border.withOpacity(.7)),
      ),
      child: child,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact info', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Refresh contact info',
            onPressed: refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refreshAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            if (profileError != null && person.isEmpty)
              EmptyState(icon: Icons.person_off_outlined, title: 'Profile unavailable', text: profileError!)
            else ...[
              if (loadingProfile) const LinearProgressIndicator(),
              if (profileError != null && !loadingProfile)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    color: OsColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.cloud_off_outlined, color: OsColors.amber),
                      title: Text('Could not load the full profile: $profileError',
                          style: const TextStyle(fontSize: 12)),
                      trailing: TextButton(onPressed: refreshAll, child: const Text('Retry')),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              // WhatsApp-inspired contact header: prominent photo, name and presence.
              Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: openPhoto,
                  child: Hero(
                    tag: 'os-profile-${widget.userId}',
                    child: AvatarPhoto(user: person, radius: 76),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(name, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 25, fontWeight: admin ? FontWeight.w900 : FontWeight.w800, letterSpacing: -.4, color: admin ? kAdminGold : null))),
                  if (verified) Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: UserBadge(user: person, size: 21),
                  ),
                ]),
              ),
              const SizedBox(height: 7),
              Center(child: Text(
                admin ? 'OS Support' : (phone.isNotEmpty ? phone : (city.isNotEmpty ? city : 'OS Dating member')),
                style: const TextStyle(color: OsColors.muted, fontSize: 14),
              )),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.circle, size: 9, color: online ? Colors.green : OsColors.muted),
                const SizedBox(width: 7),
                Text(presenceText(person), style: const TextStyle(color: OsColors.muted, fontSize: 12)),
                if (verified) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.verified_user_outlined, size: 14, color: badgeColorFor(person)),
                  const SizedBox(width: 4),
                  Text(admin ? 'OS Support' : 'Verified', style: TextStyle(color: badgeColorFor(person), fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ]),
              const SizedBox(height: 22),
              // Familiar compact contact shortcuts, retaining OS brand colors.
              Row(children: [
                Expanded(child: _ContactAction(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Message',
                  onTap: loadingProfile ? null : openChat,
                )),
                const SizedBox(width: 10),
                Expanded(child: _ContactAction(
                  icon: Icons.photo_library_outlined,
                  label: 'Posts',
                  onTap: () => Scrollable.ensureVisible(
                    // The posts heading is located below; the button scrolls to it through a key.
                    _postsSectionKey.currentContext ?? context,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  ),
                )),
              ]),
              const SizedBox(height: 18),
              VoiceBioCard(userId: widget.userId),
              if (bio.isNotEmpty) ...[
                sectionCard(child: infoRow(icon: Icons.info_outline_rounded, title: 'About', value: bio)),
                const SizedBox(height: 12),
              ],
              if (phone.isNotEmpty || city.isNotEmpty || verified) ...[
                sectionCard(child: Column(children: [
                  if (phone.isNotEmpty) infoRow(icon: Icons.phone_outlined, title: 'Phone', value: phone),
                  if (phone.isNotEmpty && (city.isNotEmpty || verified)) const Divider(height: 1, color: OsColors.border),
                  if (city.isNotEmpty) infoRow(icon: Icons.location_on_outlined, title: 'Location', value: city),
                  if (city.isNotEmpty && verified) const Divider(height: 1, color: OsColors.border),
                  if (verified) infoRow(icon: Icons.verified_user_outlined, title: 'Account status', value: accountStatusLabel(person)),
                ])),
                const SizedBox(height: 18),
              ],
              Container(
                key: _postsSectionKey,
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Row(children: [
                  const Expanded(child: Text('Media and posts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                  Text('${posts.length}', style: const TextStyle(color: OsColors.muted)),
                ]),
              ),
              if (loadingPosts)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
              else if (postsError != null)
                EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load posts', text: postsError!)
              else if (posts.isEmpty)
                sectionCard(child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(children: [
                    Icon(Icons.photo_library_outlined, size: 30, color: OsColors.muted),
                    SizedBox(height: 9),
                    Text('No posts yet', style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Photos and posts shared by this person will appear here.', textAlign: TextAlign.center, style: TextStyle(color: OsColors.muted, fontSize: 12)),
                  ]),
                ))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: posts.length,
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 230, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .76,
                  ),
                  itemBuilder: (context, index) => PostGridTile(post: mapOf(posts[index]), onChanged: loadPosts),
                ),
            ],
          ],
        ),
      ),
    );
  }

  final GlobalKey _postsSectionKey = GlobalKey();

}


class _ContactAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ContactAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: OsColors.surface,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), border: Border.all(color: OsColors.border.withOpacity(.75))),
        child: Column(children: [
          Icon(icon, color: OsColors.purple, size: 23),
          const SizedBox(height: 7),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      ),
    ),
  );
}

// ============================================================
// FEED
// ============================================================

class Feed extends StatefulWidget {
  final Map<String, dynamic> user;

  /// Lets the Get started card jump to another tab (0 feed â€¦ 4 you).
  final ValueChanged<int>? onGoTab;

  const Feed({super.key, required this.user, this.onGoTab});

  @override
  State<Feed> createState() => _FeedState();
}

class _FeedState extends State<Feed> {
  String gender = 'all';
  bool loading = true;
  List<dynamic> posts = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final result = await Api.feed(gender);
      if (!mounted) return;
      setState(() {
        // The status timeline is for other people; your own content remains
        // available from your profile.
        posts = result.where((item) => item is Map).toList();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      message('Could not load the feed: $e');
    }
  }

  Future<void> openComposer([StatusPick pick = StatusPick.none]) async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => CreateStatusScreen(
          user: widget.user,
          initialPick: pick,
        ),
      ),
    );

    if (posted == true) {
      message('Status published.');
      await load();
    }
  }

  Future<void> openVoiceStatus() async {
    final posted = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => const VoiceStatusScreen(),
      ),
    );
    if (posted == true) {
      message('Voice status published.');
      await load();
    }
  }

  List<OsStep> _getStartedSteps() {
    final u = widget.user;
    final go = widget.onGoTab;
    return [
      OsStep(
        icon: Icons.camera_alt_rounded,
        title: 'Add a profile photo',
        done: '${u['profile_photo_key'] ?? ''}'.trim().isNotEmpty,
        onTap: go == null ? null : () => go(4),
      ),
      OsStep(
        icon: Icons.edit_note_rounded,
        title: 'Write a short bio',
        done: '${u['bio'] ?? ''}'.trim().isNotEmpty,
        onTap: go == null ? null : () => go(4),
      ),
      OsStep(
        icon: Icons.verified_rounded,
        title: 'Get verified to unlock chats',
        done: isVerifiedUser(u) || isAdminUser(u),
        onTap: go == null ? null : () => go(3),
      ),
      OsStep(
        icon: Icons.explore_rounded,
        title: 'Discover people near you',
        done: false,
        onTap: go == null ? null : () => go(1),
      ),
    ];
  }

  Widget composerBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OsColors.purple.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: OsColors.purpleDeep.withValues(alpha: .16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          AvatarPhoto(user: widget.user, radius: 20),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => openComposer(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: OsColors.surface2,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  "What's on your mind?",
                  style: TextStyle(color: OsColors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Photo',
            icon: const Icon(Icons.image_outlined, color: OsColors.purple),
            onPressed: () => openComposer(StatusPick.photo),
          ),
          IconButton(
            tooltip: 'Video',
            icon: const Icon(
              Icons.video_library_outlined,
              color: OsColors.purple,
            ),
            onPressed: () => openComposer(StatusPick.video),
          ),
          IconButton(
            tooltip: 'Voice',
            icon: const Icon(Icons.mic_none_rounded, color: OsColors.purple),
            onPressed: openVoiceStatus,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const OsScreenHeader(
            title: 'Feed',
            subtitle: 'Fresh moments from real people on OS.',
            icon: Icons.dynamic_feed_rounded,
          ),
          OsGetStartedCard(steps: _getStartedSteps()),
          composerBar(),
          const SizedBox(height: 20),
          const OsSectionTitle('Status feed', icon: Icons.bolt_rounded),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in const [
                ['all', 'Everyone', Icons.public_rounded],
                ['female', 'Women', Icons.female_rounded],
                ['male', 'Men', Icons.male_rounded],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OsPill(
                    label: f[1] as String,
                    icon: f[2] as IconData,
                    selected: gender == f[0],
                    onTap: () {
                      if (gender == f[0]) return;
                      setState(() => gender = f[0] as String);
                      load();
                    },
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (posts.isEmpty)
            const EmptyState(
              icon: Icons.dynamic_feed_outlined,
              title: 'Nothing here yet',
              text: 'Be the first to share a moment with the OS community.',
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: posts.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.76,
              ),
              itemBuilder: (context, index) => PostGridTile(
                post: mapOf(posts[index]),
                onChanged: load,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// CREATE STATUS SCREEN (full-screen composer: text, photo or video)
// ============================================================

enum StatusPick { none, photo, video }

const int kMaxVideoBytes = 100 * 1024 * 1024; // 100 MB
const int kMaxImageBytes = 15 * 1024 * 1024; // 15 MB
const int kMaxStatusChars = 500;

String mimeForPath(String path, {required bool video}) {
  final p = path.toLowerCase();
  if (video) {
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.webm')) return 'video/webm';
    if (p.endsWith('.m4v')) return 'video/x-m4v';
    return 'video/mp4';
  }
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
}

class CreateStatusScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final StatusPick initialPick;

  const CreateStatusScreen({
    super.key,
    required this.user,
    this.initialPick = StatusPick.none,
  });

  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final controller = TextEditingController();
  final focus = FocusNode();

  XFile? media;
  bool isVideo = false;
  VideoPlayerController? preview;
  bool previewFailed = false;

  bool submitting = false;
  String stage = '';

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.initialPick != StatusPick.none) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        chooseMedia(video: widget.initialPick == StatusPick.video);
      });
    }
  }

  @override
  void dispose() {
    preview?.dispose();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  bool get hasText => controller.text.trim().isNotEmpty;
  bool get canPost => !submitting && (hasText || media != null);
  bool get dirty => hasText || media != null;

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> chooseMedia({required bool video}) async {
    if (submitting) return;

    try {
      final picker = ImagePicker();
      final file = video
          ? await picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 3),
            )
          : await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 88,
              maxWidth: 2048,
            );

      if (file == null || !mounted) return;

      final size = await file.length();
      final limit = video ? kMaxVideoBytes : kMaxImageBytes;
      if (size > limit) {
        toast(
          'That ${video ? 'video' : 'photo'} is too large '
          '(max ${limit ~/ (1024 * 1024)} MB).',
        );
        return;
      }

      clearMedia();
      if (!mounted) return;
      setState(() {
        media = file;
        isVideo = video;
        previewFailed = false;
      });

      if (video) await initPreview(file.path);
    } catch (e) {
      toast('Could not select media. ${Api.friendlyError(e)}');
    }
  }

  Future<void> initPreview(String path) async {
    final player = VideoPlayerController.file(File(path));
    preview = player;

    try {
      await player.initialize();
      // Cleared or screen closed while loading: whoever cleared it disposed it.
      if (!mounted || preview != player) return;
      await player.setLooping(true);
      await player.setVolume(0);
      await player.play();
      if (mounted && preview == player) setState(() {});
    } catch (_) {
      if (mounted && preview == player) {
        setState(() => previewFailed = true);
      }
    }
  }

  void clearMedia() {
    final old = preview;
    preview = null;

    if (mounted) {
      setState(() {
        media = null;
        isVideo = false;
        previewFailed = false;
      });
    }

    // Dispose after the frame so the VideoPlayer widget is gone first.
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  Future<void> submit() async {
    if (!canPost) return;
    FocusScope.of(context).unfocus();

    setState(() {
      submitting = true;
      stage = media != null
          ? 'Uploading ${isVideo ? 'video' : 'photo'}...'
          : 'Publishing...';
    });

    try {
      String? mediaKey;

      if (media != null) {
        final upload = await Api.upload(
          File(media!.path),
          'post',
          mimeForPath(media!.path, video: isVideo),
        );

        mediaKey = (upload['object_key'] ?? upload['key'])?.toString();
        if (mediaKey == null || mediaKey.isEmpty) {
          throw Exception('The upload did not return a media key.');
        }
        if (mounted) setState(() => stage = 'Publishing...');
      }

      await Api.createPost(controller.text.trim(), mediaKey);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => submitting = false);
      toast('Could not publish status. ${Api.friendlyError(e)}');
    }
  }

  Future<void> confirmDiscard() async {
    if (submitting) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this status?'),
        content: const Text('What you wrote or picked will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (discard == true && mounted) Navigator.pop(context);
  }

  double _textSize(int length) {
    if (length <= 30) return 30;
    if (length <= 70) return 25;
    if (length <= 150) return 21;
    if (length <= 300) return 18;
    return 16;
  }

  Widget _textCard() {
    return GestureDetector(
      onTap: focus.requestFocus,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 280),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: kStatusBackgrounds[0],
          borderRadius: BorderRadius.circular(22),
        ),
        alignment: Alignment.center,
        child: TextField(
          controller: controller,
          focusNode: focus,
          enabled: !submitting,
          autofocus: widget.initialPick == StatusPick.none,
          minLines: 1,
          maxLines: null,
          maxLength: kMaxStatusChars,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: Colors.white,
          style: TextStyle(
            color: Colors.white,
            fontSize: _textSize(controller.text.length),
            height: 1.3,
            fontWeight: FontWeight.w800,
          ),
          decoration: const InputDecoration(
            hintText: 'Type a status',
            hintStyle: TextStyle(color: Colors.white54),
            counterText: '',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _mediaPreview() {
    final player = preview;
    Widget body;

    if (!isVideo) {
      body = Image.file(
        File(media!.path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white),
        ),
      );
    } else if (previewFailed) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam, color: Colors.white, size: 40),
              const SizedBox(height: 8),
              Text(
                media!.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 4),
              const Text(
                'Preview unavailable, but you can still post it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    } else if (player == null || !player.value.isInitialized) {
      body = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else {
      body = GestureDetector(
        onTap: () => setState(() {
          player.value.isPlaying ? player.pause() : player.play();
        }),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: player.value.aspectRatio > 0
                    ? player.value.aspectRatio
                    : 9 / 16,
                child: VideoPlayer(player),
              ),
            ),
            if (!player.value.isPlaying)
              const Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 56,
              ),
            Positioned(
              left: 10,
              bottom: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      formatDuration(player.value.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Container(
            color: Colors.black,
            width: double.infinity,
            height: 380,
            child: body,
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: submitting ? null : clearMedia,
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(Icons.close, size: 20, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = safeName(widget.user['display_name']);
    final length = controller.text.length;

    return PopScope(
      canPop: !dirty && !submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text('New status'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: canPost ? submit : null,
                child: const Text('Post'),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              children: [
                Row(
                  children: [
                    AvatarPhoto(user: widget.user, radius: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'Shown in the status feed',
                            style: TextStyle(
                              color: OsColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (media == null) _textCard() else _mediaPreview(),
                const SizedBox(height: 14),
                if (media != null) ...[
                  TextField(
                    controller: controller,
                    focusNode: focus,
                    enabled: !submitting,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: kMaxStatusChars,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Add a caption...',
                      counterText: '',
                      prefixIcon: Icon(Icons.short_text),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$length/$kMaxStatusChars',
                    style: TextStyle(
                      fontSize: 11,
                      color: length > kMaxStatusChars - 30
                          ? Colors.orangeAccent
                          : OsColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: (media != null && !isVideo)
                          ? FilledButton.tonalIcon(
                              onPressed: submitting
                                  ? null
                                  : () => chooseMedia(video: false),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Change photo'),
                            )
                          : OutlinedButton.icon(
                              onPressed: submitting
                                  ? null
                                  : () => chooseMedia(video: false),
                              icon: const Icon(Icons.image_outlined),
                              label: const Text('Photo'),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: (media != null && isVideo)
                          ? FilledButton.tonalIcon(
                              onPressed: submitting
                                  ? null
                                  : () => chooseMedia(video: true),
                              icon: const Icon(Icons.video_library_outlined),
                              label: const Text('Change video'),
                            )
                          : OutlinedButton.icon(
                              onPressed: submitting
                                  ? null
                                  : () => chooseMedia(video: true),
                              icon: const Icon(Icons.video_library_outlined),
                              label: const Text('Video'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  media == null
                      ? 'Text statuses get a coloured background automatically.'
                      : 'Videos can be up to 3 minutes and '
                          '${kMaxVideoBytes ~/ (1024 * 1024)} MB.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: OsColors.muted, fontSize: 11),
                ),
              ],
            ),
            if (submitting)
              Positioned.fill(
                child: AbsorbPointer(
                  child: Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 22,
                      ),
                      decoration: BoxDecoration(
                        color: OsColors.surface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 14),
                          Text(
                            stage,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (isVideo) ...[
                            const SizedBox(height: 4),
                            const Text(
                              'Videos can take a moment. Keep this open.',
                              style: TextStyle(
                                color: OsColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TEXT STATUS CARD (bold, centered, auto-sized)
// ============================================================

const List<Color> kStatusBackgrounds = [
  Color(0xFF302044),
  Color(0xFF173B42),
  Color(0xFF493021),
  Color(0xFF263A59),
  Color(0xFF493044),
  Color(0xFF304333),
  Color(0xFF514024),
  Color(0xFF34334E),
];

/// Same post always gets the same background colour.
Color statusBackgroundFor(Map<String, dynamic> post) {
  final id = int.tryParse('${post['id'] ?? ''}');
  final text = '${post['text'] ?? ''}';
  final index = ((id ?? text.hashCode).abs()) % kStatusBackgrounds.length;
  return kStatusBackgrounds[index];
}

/// Text-only status: centered, bold, font size shrinks as the text grows
/// so short statuses look big and long ones still fit neatly.
class StatusTextCard extends StatelessWidget {
  final String text;
  final Color background;
  final bool compact;

  const StatusTextCard({
    super.key,
    required this.text,
    required this.background,
    this.compact = true,
  });

  double _fontSize(int length) {
    if (compact) {
      if (length <= 30) return 20;
      if (length <= 70) return 17;
      if (length <= 130) return 15;
      return 13;
    }
    if (length <= 30) return 30;
    if (length <= 70) return 25;
    if (length <= 150) return 21;
    if (length <= 300) return 18;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    final clean = text.trim().isEmpty ? 'Status update' : text.trim();

    return Container(
      width: double.infinity,
      constraints: compact ? null : const BoxConstraints(minHeight: 260),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 24,
        vertical: compact ? 14 : 32,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: compact ? null : BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        clean,
        textAlign: TextAlign.center,
        maxLines: compact ? 8 : null,
        overflow: compact ? TextOverflow.ellipsis : TextOverflow.visible,
        style: TextStyle(
          color: Colors.white,
          fontSize: _fontSize(clean.length),
          height: 1.3,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ============================================================
// POST GRID TILE: BOLD TEXT STATUS + WORKING LIKE BUTTON
// ============================================================

class PostGridTile extends StatefulWidget {
  final Map<String, dynamic> post;
  final Future<void> Function()? onChanged;

  const PostGridTile({
    super.key,
    required this.post,
    this.onChanged,
  });

  @override
  State<PostGridTile> createState() => _PostGridTileState();
}

class _PostGridTileState extends State<PostGridTile> {
  late Map<String, dynamic> post;
  bool liking = false;

  @override
  void initState() {
    super.initState();
    post = Map<String, dynamic>.from(widget.post);
  }

  @override
  void didUpdateWidget(covariant PostGridTile oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldId = '${oldWidget.post['id'] ?? ''}';
    final newId = '${widget.post['id'] ?? ''}';

    if (oldId != newId || !liking) {
      post = Map<String, dynamic>.from(widget.post);
    }
  }

  int get postId => int.tryParse('${post['id'] ?? ''}') ?? 0;

  bool get likedByMe => post['liked_by_me'] == true;

  int get likesCount =>
      int.tryParse('${post['like_count'] ?? post['likes_count'] ?? 0}') ?? 0;

  Future<void> toggleLike() async {
    if (liking || postId <= 0) return;

    final wasLiked = likedByMe;
    final oldCount = likesCount;

    setState(() {
      liking = true;
      post['liked_by_me'] = !wasLiked;
      post['like_count'] = (oldCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
    });

    try {
      final result = wasLiked
          ? await Api.unlikePost(postId)
          : await Api.likePost(postId);

      if (!mounted) return;

      setState(() {
        post['liked_by_me'] = result['liked_by_me'] ?? !wasLiked;
        post['like_count'] =
            result['like_count'] ?? result['likes_count'] ?? post['like_count'];
        liking = false;
      });

      await widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        post['liked_by_me'] = wasLiked;
        post['like_count'] = oldCount;
        liking = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like. ${Api.friendlyError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = mapOf(post['author']);
    final text = '${post['text'] ?? ''}'.trim();
    final mediaKey = '${post['media_key'] ?? ''}';
    final hasMedia = mediaKey.isNotEmpty;

    return Material(
      color: OsColors.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => PostDetailScreen(post: post),
            ),
          );
          await widget.onChanged?.call();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: hasMedia
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        MediaThumb(
                          keyValue: mediaKey,
                          compact: true,
                          openOnTap: false,
                        ),
                        if (text.isNotEmpty)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 22, 10, 8),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black87],
                                ),
                              ),
                              child: Text(
                                text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : StatusTextCard(
                      text: text,
                      background: statusBackgroundFor(post),
                      compact: true,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 7, 7),
              child: Row(
                children: [
                  UserTap(
                    user: author,
                    child: AvatarPhoto(user: author, radius: 15),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: UserTap(
                      user: author,
                      child: Text(
                        safeName(author['display_name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: likedByMe ? 'Unlike post' : 'Like post',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 32,
                    ),
                    onPressed: liking ? null : toggleLike,
                    icon: Icon(
                      likedByMe ? Icons.favorite : Icons.favorite_border,
                      size: 17,
                      color: likedByMe ? Colors.redAccent : null,
                    ),
                  ),
                  Text(
                    '$likesCount',
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// POST DETAIL: LIKE + PRIVATE REPLY (goes to the author's DM)
// ============================================================

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Map<String, dynamic> post;
  final replyController = TextEditingController();

  bool sendingReply = false;
  bool liking = false;

  @override
  void initState() {
    super.initState();
    post = Map<String, dynamic>.from(widget.post);
  }

  @override
  void dispose() {
    replyController.dispose();
    super.dispose();
  }

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  int get postId => int.tryParse('${post['id']}') ?? 0;

  bool get likedByMe => post['liked_by_me'] == true;

  int get likesCount =>
      int.tryParse('${post['like_count'] ?? post['likes_count'] ?? 0}') ?? 0;

  Future<void> toggleLike() async {
    if (liking || postId <= 0) return;

    final wasLiked = likedByMe;
    final oldCount = likesCount;

    setState(() {
      liking = true;
      post['liked_by_me'] = !wasLiked;
      post['like_count'] = (oldCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 30);
    });

    try {
      final result = wasLiked
          ? await Api.unlikePost(postId)
          : await Api.likePost(postId);

      if (!mounted) return;
      setState(() {
        post['liked_by_me'] = result['liked_by_me'] ?? !wasLiked;
        post['like_count'] =
            result['like_count'] ?? result['likes_count'] ?? post['like_count'];
        liking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        post['liked_by_me'] = wasLiked;
        post['like_count'] = oldCount;
        liking = false;
      });
      message('Could not update like: $e');
    }
  }

  Future<void> sendReply() async {
    final text = replyController.text.trim();
    if (text.isEmpty || sendingReply || postId <= 0) return;

    final authorId = '${mapOf(post['author'])['id'] ?? post['user_id'] ?? ''}';
    if (authorId.isNotEmpty && authorId == currentUserId) return;

    setState(() => sendingReply = true);

    try {
      // Private: delivered only to the status owner's DM. Nothing is
      // posted publicly under the status.
      final sent = await Api.request(
        'POST',
        '/posts/$postId/reply',
        body: {'body': text},
      );

      replyController.clear();

      if (!mounted) return;
      setState(() => sendingReply = false);

      // Open the author's DM so the person sees their reply in the chat.
      final conversationId = int.tryParse('${sent['conversation_id']}');
      if (conversationId == null) {
        message('Reply sent.');
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(
            conversationId: conversationId,
            person: mapOf(post['author']),
            profileBuilder: (id, profile) => PublicProfileScreen(
              userId: id,
              initialUser: profile,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => sendingReply = false);
      message('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = mapOf(post['author']);
    final authorName = safeName(author['display_name']);
    final text = '${post['text'] ?? ''}';
    final mediaKey = '${post['media_key'] ?? ''}';
    final hasMedia = mediaKey.isNotEmpty;
    final isMine = currentUserId.isNotEmpty &&
        '${author['id'] ?? post['user_id'] ?? ''}' == currentUserId;

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          UserTap(
            user: author,
            child: Row(
              children: [
                AvatarPhoto(user: author, radius: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              authorName,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: isAdminUser(author) ? kAdminGold : null,
                              ),
                            ),
                          ),
                          if (isVerifiedUser(author))
                            Padding(
                              padding: const EdgeInsets.only(left: 5),
                              child: UserBadge(user: author, size: 16),
                            ),
                        ],
                      ),
                      Text(
                        [
                          if ('${author['city'] ?? ''}'.trim().isNotEmpty)
                            '${author['city']}',
                          if ('${author['gender'] ?? ''}'.trim().isNotEmpty)
                            '${author['gender']}',
                        ].join(' Â· '),
                        style: const TextStyle(
                          color: OsColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!hasMedia && text.trim().isNotEmpty)
            StatusTextCard(
              text: text,
              background: statusBackgroundFor(post),
              compact: false,
            )
          else if (text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (hasMedia) ...[
            const SizedBox(height: 8),
            MediaThumb(
              keyValue: mediaKey,
              compact: false,
              openOnTap: true,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                tooltip: likedByMe ? 'Unlike post' : 'Like post',
                onPressed: liking ? null : toggleLike,
                icon: Icon(
                  likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: likedByMe ? Colors.redAccent : null,
                ),
              ),
              Text(
                '$likesCount ${likesCount == 1 ? 'like' : 'likes'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(height: 26),
          if (isMine)
            const Text(
              'This is your post. Replies from other people will arrive in your chats.',
              style: TextStyle(color: OsColors.muted, fontSize: 12),
            )
          else ...[
            Text(
              'Reply to $authorName',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Your reply goes to their DM. Nobody else can see it.',
              style: TextStyle(color: OsColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: replyController,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Reply privately...',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: sendingReply ? null : sendReply,
                  icon: sendingReply
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// MEDIA THUMBNAIL AND VIEWER
// ============================================================

class MediaThumb extends StatefulWidget {
  final String keyValue;
  final bool compact;
  final bool openOnTap;

  const MediaThumb({
    super.key,
    required this.keyValue,
    this.compact = false,
    this.openOnTap = true,
  });

  @override
  State<MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<MediaThumb> {
  String? url;
  bool failed = false;

  bool get isAudio {
    final key = widget.keyValue.toLowerCase().split('?').first;
    return key.endsWith('.m4a') || key.endsWith('.aac') || key.endsWith('.mp3');
  }

  bool get isVideo {
    final key = widget.keyValue.toLowerCase().split('?').first;
    return key.endsWith('.mp4') ||
        key.endsWith('.mov') ||
        key.endsWith('.m4v') ||
        key.endsWith('.webm');
  }

  @override
  void initState() {
    super.initState();
    loadUrl();
  }

  @override
  void didUpdateWidget(covariant MediaThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyValue != widget.keyValue) {
      url = null;
      failed = false;
      loadUrl();
    }
  }

  Future<void> loadUrl() async {
    try {
      final result = await Api.mediaUrl(widget.keyValue);
      if (!mounted) return;
      setState(() => url = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => failed = true);
    }
  }

  void openViewer() {
    if (!widget.openOnTap || url == null || url!.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullScreenMediaViewer(url: url!, isVideo: isVideo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isAudio) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 0 : 18),
        child: SizedBox(
          width: double.infinity,
          height: widget.compact ? double.infinity : 280,
          child: VoiceClipPlayer(
            key: ValueKey(widget.keyValue),
            loadUrl: () => Api.mediaUrl(widget.keyValue),
            compact: widget.compact,
            label: 'Voice status',
          ),
        ),
      );
    }
    final child = failed
        ? const Center(child: Icon(Icons.broken_image_outlined))
        : url == null
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (isVideo)
                    Container(
                      color: Colors.black,
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    )
                  else
                    Image.network(
                      url!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  if (isVideo)
                    const Positioned(
                      right: 8,
                      bottom: 8,
                      child: Icon(
                        Icons.videocam_outlined,
                        color: Colors.white,
                      ),
                    ),
                ],
              );

    return GestureDetector(
      onTap: widget.openOnTap ? openViewer : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.compact ? 0 : 18),
        child: SizedBox(
          width: double.infinity,
          height: widget.compact ? double.infinity : 280,
          child: child,
        ),
      ),
    );
  }
}

class FullScreenMediaViewer extends StatefulWidget {
  final String url;
  final bool isVideo;

  const FullScreenMediaViewer({
    super.key,
    required this.url,
    required this.isVideo,
  });

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  VideoPlayerController? controller;
  String? videoError;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) initializeVideo();
  }

  Future<void> initializeVideo() async {
    final player = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    controller = player;
    try {
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return;
      }
      await player.setLooping(true);
      await player.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        videoError = 'Could not play this video. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.isVideo ? 'Video status' : 'Photo'),
      ),
      body: SafeArea(
        child: Center(
          child: widget.isVideo
              ? _video(player)
              : InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    widget.url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _video(VideoPlayerController? player) {
    if (videoError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          videoError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    if (player == null || !player.value.isInitialized) {
      return const CircularProgressIndicator(color: Colors.white);
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio:
              player.value.aspectRatio > 0 ? player.value.aspectRatio : 9 / 16,
          child: VideoPlayer(player),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: VideoProgressIndicator(player, allowScrubbing: true),
        ),
        IconButton(
          color: Colors.white,
          iconSize: 38,
          onPressed: () {
            setState(() {
              if (player.value.isPlaying) {
                player.pause();
              } else {
                player.play();
              }
            });
          },
          icon: Icon(
            player.value.isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// DISCOVER
// ============================================================

class Discover extends StatefulWidget {
  final Map<String, dynamic> user;

  const Discover({super.key, required this.user});

  @override
  State<Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<Discover> {
  String gender = 'all';
  bool nearby = false;
  bool locating = false;
  double? myLat;
  double? myLng;
  double radiusKm = 100;
  bool loading = false;
  bool postsLoading = true;
  List<dynamic> people = [];
  List<dynamic> mediaPosts = [];

  final search = TextEditingController();
  final cityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    load();
    loadPosts();
    // Location is opt-in. Do not keep prompting for GPS when Discover opens.
  }

  @override
  void dispose() {
    search.dispose();
    cityController.dispose();
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final result = await Api.discover(
        gender: gender,
        q: search.text.trim(),
        city: cityController.text.trim(),
        nearby: nearby,
        radiusKm: radiusKm,
        latitude: nearby ? myLat : null,
        longitude: nearby ? myLng : null,
      );
      if (!mounted) return;
      setState(() {
        people = result.where((item) {
          if (item is! Map) return false;
          return !_belongsToCurrentUser(item, widget.user, idIsUser: true);
        }).toList();
        // Closest first when GPS distances are available.
        double dist(dynamic e) =>
            double.tryParse('${e is Map ? e['distance_km'] : ''}') ?? double.infinity;
        if (nearby) people.sort((a, b) => dist(a).compareTo(dist(b)));
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      message('Search failed: $e');
    }
  }

  Future<void> loadPosts() async {
    setState(() => postsLoading = true);
    try {
      final result = await Api.feed(gender);
      if (!mounted) return;
      setState(() {
        mediaPosts = result.where((item) {
          if (item is! Map) return false;
          return !_belongsToCurrentUser(item, widget.user) &&
              '${item['media_key'] ?? ''}'.trim().isNotEmpty;
        }).toList();
        postsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => postsLoading = false);
      message('Could not load posts: $e');
    }
  }

  /// If location is already allowed, quietly switch Nearby on at start-up.
  Future<void> _autoLocate() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Never asked yet: show the system permission prompt.
        await locate();
        return;
      }
      final allowed = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      if (!allowed || !await Geolocator.isLocationServiceEnabled()) return;
      await locate(silent: true);
    } catch (_) {}
  }

  Future<Position?> _currentPosition({required bool silent}) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && !silent) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.unableToDetermine) {
      if (!silent) {
        message('This device could not report its location permission state. '
            'Fully close and reinstall the app, then try again.');
      }
      return null;
    }
    if (permission == LocationPermission.denied) {
      if (!silent) {
        message('Location permission was denied. Allow it to find nearby people.');
      }
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      if (silent || !mounted) return null;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Location permission needed'),
          content: const Text(
            'OS needs location access to find people nearby. Enable location permission in your device settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Geolocator.openAppSettings();
              },
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (silent || !mounted) return null;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Turn on location'),
          content: const Text(
            'Your device location service is turned off. Turn it on to find people nearby.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Geolocator.openLocationSettings();
              },
              child: const Text('Location settings'),
            ),
          ],
        ),
      );
      return null;
    }
    try {
      // A fresh GPS fix can hang indoors, so cap it and fall back to the
      // last position the phone knows.
      return await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null && !silent) {
        message('Could not get your location. Check that GPS is on and try again.');
      }
      return last;
    }
  }

  Future<void> locate({bool silent = false}) async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final position = await _currentPosition(silent: silent);
      if (position == null) return;
      myLat = position.latitude;
      myLng = position.longitude;
      // Save so other members see a distance to you; discovery still works
      // if this write fails because the coordinates are also sent below.
      try {
        await Api.profile({'latitude': myLat, 'longitude': myLng});
      } catch (_) {}
      if (!mounted) return;
      setState(() => nearby = true);
      await load();
    } catch (e) {
      if (!silent) message('Location error: $e');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  void stopNearby() {
    setState(() => nearby = false);
    load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([load(), loadPosts()]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const OsScreenHeader(
            title: 'Discover',
            subtitle: 'Find your kind of person by name, city or distance.',
            icon: Icons.explore_rounded,
          ),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              hintText: 'Search by name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(6),
                child: OsIconBtn(
                  icon: Icons.arrow_forward_rounded,
                  active: true,
                  size: 40,
                  onPressed: load,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: gender,
                  decoration: const InputDecoration(labelText: 'Show'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Everyone')),
                    DropdownMenuItem(value: 'female', child: Text('Women')),
                    DropdownMenuItem(value: 'male', child: Text('Men')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => gender = value);
                    load();
                    loadPosts();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: cityController,
                  enabled: !nearby,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => load(),
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'e.g. Lagos',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OsButton(
            kind: OsBtnKind.secondary,
            busy: locating,
            icon: Icons.near_me_rounded,
            label: nearby ? 'Refresh my location' : 'Find people nearby',
            onPressed: (loading || locating) ? null : () => locate(),
          ),
          if (nearby) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: true,
              onChanged: (_) => stopNearby(),
              title: const Text('Nearby only'),
              subtitle: const Text('Sorted by distance from you'),
            ),
            Row(
              children: [
                const Expanded(child: Text('Maximum distance')),
                Text('${radiusKm.round()} km'),
              ],
            ),
            Slider(
              value: radiusKm,
              min: 1,
              max: 500,
              divisions: 499,
              label: '${radiusKm.round()} km',
              onChanged: (v) => setState(() => radiusKm = v),
              onChangeEnd: (_) => load(),
            ),
          ],
          const SizedBox(height: 10),
          OsButton(
            icon: Icons.search_rounded,
            label: 'Search people',
            busy: loading,
            onPressed: load,
          ),
          const SizedBox(height: 26),
          OsSectionTitle(
            'Photos & Videos',
            icon: Icons.photo_library_rounded,
            trailing: OsIconBtn(
              icon: Icons.refresh_rounded,
              size: 38,
              tooltip: 'Refresh',
              onPressed: postsLoading ? null : loadPosts,
            ),
          ),
          const SizedBox(height: 4),
          if (postsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (mediaPosts.isEmpty)
            const Text(
              'No photo or video posts yet.',
              style: TextStyle(color: OsColors.muted),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: mediaPosts.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                crossAxisSpacing: 7,
                mainAxisSpacing: 7,
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, index) {
                final post = mapOf(mediaPosts[index]);
                return Material(
                  color: OsColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => PostDetailScreen(post: post),
                        ),
                      );
                      await loadPosts();
                    },
                    child: MediaThumb(
                      keyValue: '${post['media_key']}',
                      compact: true,
                      openOnTap: false,
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 24),
          const OsSectionTitle('People', icon: Icons.people_alt_rounded),
          const SizedBox(height: 4),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (people.isEmpty)
            Column(
              children: [
                EmptyState(
                  icon: Icons.people_outline,
                  title: 'No people found',
                  text: nearby
                      ? 'No one within ${radiusKm.round()} km. Try a larger distance.'
                      : 'Try another name, city or search preference.',
                ),
                if (nearby)
                  TextButton(
                    onPressed: stopNearby,
                    child: const Text('Show everyone instead'),
                  ),
              ],
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: people.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.62,
              ),
              itemBuilder: (context, index) => PersonGridCard(
                item: people[index],
                user: widget.user,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// PERSON GRID CARD (full photo, verified badge, presence, clear button)
// ============================================================

class PersonGridCard extends StatelessWidget {
  final dynamic item;
  final Map<String, dynamic> user;

  const PersonGridCard({
    super.key,
    required this.item,
    required this.user,
  });

  Future<void> _connect(
      BuildContext context, Map<String, dynamic> person) async {
    try {
      final id = int.tryParse('${person['id']}');
      if (id == null) throw Exception('Invalid user ID.');

      await Api.connect(id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection request sent.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Api.friendlyError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = mapOf(item);
    final person = mapOf(entry['user']);
    final admin = isAdminUser(person);
    final verified = isVerifiedUser(person);
    final myVerified = isVerifiedUser(user);
    final city = '${person['city'] ?? 'Location unavailable'}';
    final distance = entry['distance_km'];
    final photoKey = '${person['profile_photo_key'] ?? ''}'.trim();
    final revealStatus = '${person['photo_reveal_status'] ?? 'not_requested'}';
    // Admin photos are never protected, and admins always see real photos.
    final photoProtected = photoKey.isNotEmpty && revealStatus != 'approved' && !currentUserIsAdmin && !admin;
    final online = isOnline(person);

    VoidCallback? onPressed;
    IconData buttonIcon;
    String buttonLabel;

    if (!myVerified) {
      // YOU are not verified: send you to verification.
      buttonIcon = Icons.lock_outline;
      buttonLabel = 'Verify to connect';
      onPressed = () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: const Text('Verify your identity'),
                ),
                body: VerificationScreen(
                  user: user,
                  onChanged: (_) {},
                ),
              ),
            ),
          );
    } else if (!verified) {
      // THEY are not verified: cannot connect.
      buttonIcon = Icons.shield_outlined;
      buttonLabel = 'Not verified';
      onPressed = null;
    } else {
      buttonIcon = Icons.favorite_border;
      buttonLabel = 'Connect';
      onPressed = () => _connect(context, person);
    }

    return Container(
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OsColors.border.withOpacity(0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: UserTap(
              user: person,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  photoKey.isNotEmpty && !photoProtected
                      ? MediaThumb(
                          keyValue: photoKey,
                          compact: true,
                          openOnTap: false,
                        )
                      : photoKey.isNotEmpty
                          ? Stack(fit: StackFit.expand, children: [
                              BlurredProfileThumb(ownerId: int.tryParse('${person['id']}') ?? 0),
                              Container(color: Colors.black.withOpacity(0.24)),
                              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.lock_outline_rounded, size: 38, color: Colors.white),
                                const SizedBox(height: 8),
                                Text(revealStatus == 'pending' ? 'Request sent' : revealStatus == 'rejected' ? 'Reveal declined' : 'Photo protected', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                                if (revealStatus != 'pending' && revealStatus != 'rejected')
                                  TextButton.icon(
                                    onPressed: () async {
                                      try {
                                        await Api.requestPhotoReveal(int.parse('${person['id']}'));
                                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reveal request sent. The owner decides whether to approve it.')));
                                      } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e)))); }
                                    },
                                    icon: const Icon(Icons.visibility_outlined, color: Colors.white), label: const Text('Request reveal', style: TextStyle(color: Colors.white)),
                                  ),
                              ])),
                            ])
                      : Container(
                          color: OsColors.surface2,
                          child: Center(
                            child: AvatarPhoto(user: person, radius: 44),
                          ),
                        ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            verified ? Icons.verified : Icons.shield_outlined,
                            size: 13,
                            color: verified ? badgeColorFor(person) : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            admin ? 'OS Support' : (verified ? 'Verified' : 'Unverified'),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        safeName(person['display_name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: isAdminUser(person) ? kAdminGold : null,
                        ),
                      ),
                    ),
                    if (verified) UserBadge(user: person, size: 15),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: online ? Colors.green : OsColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        presenceText(person),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: OsColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  distanceLabel(city, distance),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: OsColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: FilledButton.tonalIcon(
                    onPressed: onPressed,
                    icon: Icon(buttonIcon, size: 16),
                    label: Text(
                      buttonLabel,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CHATS
// ============================================================

class Chats extends StatefulWidget {
  final dynamic myId;

  const Chats({super.key, this.myId});

  @override
  State<Chats> createState() => _ChatsState();
}

class _ChatsState extends State<Chats> {
  List<dynamic> conversations = [];
  List<dynamic> connections = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final results = await Future.wait([
        Api.conversations(),
        Api.connections(),
      ]);

      if (!mounted) return;
      setState(() {
        conversations = results[0];
        connections = results[1];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not refresh chats. ${Api.friendlyError(e)}')),
      );
    }
  }

  Future<void> acceptConnection(dynamic id) async {
    try {
      final connectionId = int.tryParse('$id');
      if (connectionId == null) {
        throw Exception('Invalid connection ID.');
      }

      await Api.accept(connectionId);
      await load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection accepted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept request. ${Api.friendlyError(e)}')),
      );
    }
  }

  /// Chat-list preview that reads like WhatsApp for status interactions.
  String previewFor(Map<String, dynamic> lastMessage) {
    if (lastMessage.isEmpty) return 'Start the conversation';

    final kind = '${lastMessage['kind'] ?? 'text'}';
    final body = '${lastMessage['body'] ?? ''}'
        .replaceFirst(RegExp(r'^\?+\s*'), '')
        .trim();
    final mine =
        widget.myId != null && lastMessage['sender_id'] == widget.myId;

    if (kind == 'status_like') {
      return mine ? 'You liked their status' : '\u2764\ufe0f Liked your status';
    }
    if (kind == 'status_reply') {
      return mine
          ? 'You replied to their status'
          : 'Replied to your status: $body';
    }

    return body.isEmpty ? 'Start the conversation' : body;
  }

  @override
  Widget build(BuildContext context) {
    final pending = connections.where((entry) {
      if (entry is! Map) return false;
      return entry['incoming'] == true && entry['status'] == 'pending';
    }).toList();

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          OsScreenHeader(
            title: 'Chats',
            subtitle: 'Connect first, then start a conversation.',
            icon: Icons.chat_bubble_rounded,
            trailing: OsIconBtn(
              tooltip: 'Mark all chats as read',
              icon: Icons.done_all_rounded,
              onPressed: () async {
                try { await Api.markAllConversationsRead(); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All chats marked as read.'))); }
                catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not mark chats as read. ${Api.friendlyError(e)}'))); }
              },
            ),
          ),
          FeaturesStrip(user: {'id': widget.myId}),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            ),
          if (pending.isNotEmpty) ...[
            OsSectionTitle('Connection requests', icon: Icons.person_add_alt_1_rounded,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: OsColors.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pending.length}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.white)),
                )),
            ...pending.map((raw) {
              final connection = mapOf(raw);
              final person = mapOf(connection['user']);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: OsColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: OsColors.purple.withValues(alpha: .35)),
                ),
                child: Row(
                  children: [
                    UserTap(
                      user: person,
                      child: AvatarPhoto(user: person, radius: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: UserTap(
                        user: person,
                        child: Text(
                          '${safeName(person['display_name'])} wants to connect',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OsButton(
                      label: 'Accept',
                      icon: Icons.check_rounded,
                      expand: false,
                      height: 42,
                      onPressed: () => acceptConnection(connection['id']),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 15),
          ],
          const OsSectionTitle('Messages', icon: Icons.forum_rounded),
          ...conversations.map((raw) {
            final conversation = mapOf(raw);
            final person = mapOf(conversation['user']);
            final lastMessage = mapOf(conversation['last_message']);
            final preview = previewFor(lastMessage);

            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                color: OsColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: OsColors.border.withValues(alpha: .7)),
              ),
              child: Material(
              color: Colors.transparent,
              child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: UserTap(
                user: person,
                child: AvatarPhoto(user: person, radius: 25),
              ),
              title: UserTap(
                user: person,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        safeName(person['display_name']),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isAdminUser(person) ? FontWeight.w900 : FontWeight.w800,
                          color: isAdminUser(person) ? kAdminGold : null,
                        ),
                      ),
                    ),
                    if (isVerifiedUser(person))
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: UserBadge(user: person, size: 15),
                      ),
                  ],
                ),
              ),
              subtitle: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final id = int.tryParse('${conversation['id']}');
                if (id == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid conversation.')),
                  );
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ChatScreen(
                      conversationId: id,
                      person: person,
                      myId: widget.myId,
                      profileBuilder: (profileId, profile) => PublicProfileScreen(
                        userId: profileId,
                        initialUser: profile,
                      ),
                    ),
                  ),
                ).then((_) => load());
              },
              ),
              ),
            );
          }),
          if (!loading && conversations.isEmpty && pending.isEmpty)
            const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No chats yet',
              text: 'Discover people and send connection requests. '
                  'Accepted connections can start conversations.',
            ),
        ],
      ),
    );
  }
}

// ============================================================
// OWN PROFILE: EDITING
// ============================================================

class _ProfileFieldDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String hint;
  final int maxLines;
  final TextInputType keyboardType;

  const _ProfileFieldDialog({
    required this.title,
    required this.initialValue,
    required this.hint,
    required this.maxLines,
    required this.keyboardType,
  });

  @override
  State<_ProfileFieldDialog> createState() => _ProfileFieldDialogState();
}

class _ProfileFieldDialogState extends State<_ProfileFieldDialog> {
  late final TextEditingController draft;

  @override
  void initState() {
    super.initState();
    draft = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: draft,
        autofocus: true,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.title == 'Name'
            ? TextCapitalization.words
            : TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, draft.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class Profile extends StatefulWidget {
  final Map<String, dynamic> user;
  final void Function(Map<String, dynamic>) onChanged;
  final VoidCallback onLogout;

  const Profile({
    super.key,
    required this.user,
    required this.onChanged,
    required this.onLogout,
  });

  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  late Map<String, dynamic> u;
  final name = TextEditingController();
  final phone = TextEditingController();
  final bio = TextEditingController();
  final city = TextEditingController();
  final gender = TextEditingController();

  bool hidden = false;
  bool phoneVisible = false;
  bool saving = false;
  bool uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    applyUser(widget.user);
  }

  @override
  void didUpdateWidget(covariant Profile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) applyUser(widget.user);
  }

  void applyUser(Map<String, dynamic> value) {
    u = Map<String, dynamic>.from(value);
    name.text = '${u['display_name'] ?? ''}';
    phone.text = '${u['phone'] ?? u['phone_number'] ?? ''}';
    bio.text = '${u['bio'] ?? ''}';
    city.text = '${u['city'] ?? ''}';
    gender.text = '${u['gender'] ?? ''}';
    hidden = u['photos_hidden'] == true;
    phoneVisible = u['phone_visible'] == true;
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    bio.dispose();
    city.dispose();
    gender.dispose();
    super.dispose();
  }

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);

    try {
      final displayName = name.text.trim();
      if (displayName.isEmpty) {
        message('Please enter your name.');
        setState(() => saving = false);
        return;
      }
      final updated = await Api.profile({
        'display_name': displayName,
        'phone_number': phone.text.trim(),
        'phone_visible': phoneVisible,
        'bio': bio.text.trim(),
        'city': city.text.trim(),
        'gender': gender.text.trim(),
        'photos_hidden': hidden,
      });

      if (!mounted) return;
      setState(() {
        u = Map<String, dynamic>.from(updated);
        saving = false;
      });
      widget.onChanged(updated);
      message('Profile saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      message('Could not save profile: $e');
    }
  }

  Future<void> changePhoto() async {
    if (uploadingPhoto) return;

    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );

      if (selected == null || !mounted) return;
      setState(() => uploadingPhoto = true);

      final uploaded = await Api.upload(
        File(selected.path),
        'profile',
        selected.mimeType ?? mimeForPath(selected.path, video: false),
      );

      final key = (uploaded['object_key'] ?? uploaded['key'])?.toString();
      if (key == null || key.isEmpty) {
        throw Exception('Upload did not return a photo key.');
      }

      final updated = await Api.profile({'profile_photo_key': key});
      if (!mounted) return;

      setState(() {
        u = Map<String, dynamic>.from(updated);
        uploadingPhoto = false;
      });
      widget.onChanged(updated);
      message('Profile photo updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => uploadingPhoto = false);
      message('Could not update photo: $e');
    }
  }

  Future<void> chooseGender() async {
    final value = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Select gender')),
      for (final option in const [('male', 'Male'), ('female', 'Female')])
        ListTile(title: Text(option.$2), trailing: gender.text.toLowerCase() == option.$1 ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(ctx, option.$1)),
      const SizedBox(height: 12),
    ])));
    if (value != null && mounted) setState(() => gender.text = value);
  }

  Future<void> chooseState() async {
    final value = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (ctx) => SafeArea(child: SizedBox(height: MediaQuery.of(ctx).size.height * .72, child: Column(children: [
      const ListTile(title: Text('Select state / FCT')),
      Expanded(child: ListView.builder(itemCount: nigerianStates.length, itemBuilder: (ctx, index) { final option = nigerianStates[index]; return ListTile(title: Text(option), trailing: city.text == option ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(ctx, option)); })),
    ]))));
    if (value != null && mounted) setState(() => city.text = value);
  }

  Future<void> editProfileField({
    required String title,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    // The dialog owns its controller so it is disposed only when its route
    // actually unmounts, not immediately when Navigator.pop starts animating.
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _ProfileFieldDialog(
        title: title,
        initialValue: controller.text,
        hint: hint ?? title,
        maxLines: maxLines,
        keyboardType: keyboardType,
      ),
    );
    if (result != null && mounted) {
      setState(() => controller.text = result);
    }
  }

  Future<void> verifyEmail() async {
    final email = (u['email'] ?? '').toString().trim();
    if (email.isEmpty) {
      message('Your account email is unavailable. Please sign in again.');
      return;
    }
    try {
      await Api.sendEmailVerification(email);
      if (!mounted) return;
      final codeController = TextEditingController();
      final code = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Verify your email'),
          content: TextField(
            controller: codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration:
                InputDecoration(labelText: '6-digit code sent to $email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, codeController.text.trim()),
              child: const Text('Verify'),
            ),
          ],
        ),
      );
      codeController.dispose();
      if (code == null || code.length != 6) return;
      await Api.confirmEmailVerification(email, code);
      final updated = await Api.me();
      if (!mounted) return;
      setState(() => u = Map<String, dynamic>.from(updated));
      widget.onChanged(updated);
      message('Email verified successfully.');
    } catch (e) {
      if (mounted) message('Email verification failed: $e');
    }
  }

  Future<void> removePhoto() async {
    try {
      final updated = await Api.profile({'profile_photo_key': null});
      if (!mounted) return;
      setState(() => u = Map<String, dynamic>.from(updated));
      widget.onChanged(updated);
      message('Profile photo removed.');
    } catch (e) {
      if (!mounted) return;
      message('Could not remove photo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = safeName(name.text.isEmpty ? u['display_name'] : name.text);
    final about = bio.text.trim().isEmpty ? 'Hey there! I am using OS Dating.' : bio.text.trim();
    final hasPhoto = '${u['profile_photo_key'] ?? ''}'.trim().isNotEmpty;

    Widget profileRow({
      required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
    }) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: OsColors.muted),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(value.isEmpty ? 'Add $title' : value,
          maxLines: title == 'About' ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: value.isEmpty ? OsColors.muted : null, height: 1.3)),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 19),
      onTap: onTap,
    );

    Widget sectionLabel(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(5, 22, 5, 9),
      child: Text(label.toUpperCase(), style: const TextStyle(
        color: OsColors.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      children: [
        const OsScreenHeader(
          title: 'You',
          subtitle: 'Make your profile feel like you.',
          icon: Icons.person_rounded,
        ),
        Center(
          child: Column(children: [
            Stack(alignment: Alignment.bottomRight, children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showProfilePhoto(context, u),
                child: AvatarPhoto(user: u, radius: 58),
              ),
              Material(
                color: OsColors.surface,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Change profile photo',
                  onPressed: uploadingPhoto ? null : changePhoto,
                  icon: uploadingPhoto
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.camera_alt_outlined),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text(displayName, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (isVerifiedUser(u))
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: UserBadge(user: u, size: 14),
                ),
              Text(accountStatusLabel(u).toUpperCase(),
                style: TextStyle(
                  color: isVerifiedUser(u) ? badgeColorFor(u) : OsColors.muted,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        sectionLabel('Voice intro'),
        VoiceBioCard(userId: int.tryParse(currentUserId) ?? 0, editable: true),
        sectionLabel('Profile information'),
        Material(
          color: OsColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: OsColors.border.withOpacity(.7)),
          ),
          child: Column(children: [
            profileRow(icon: Icons.person_outline_rounded, title: 'Name', value: name.text,
              onTap: () => editProfileField(title: 'Name', controller: name, hint: 'Your name')),
            const Divider(height: 1, indent: 58),
            profileRow(icon: Icons.info_outline_rounded, title: 'About', value: bio.text,
              onTap: () => editProfileField(title: 'About', controller: bio, maxLines: 4, hint: 'A little about you')),
            const Divider(height: 1, indent: 58),
            profileRow(icon: Icons.phone_outlined, title: 'Phone', value: phone.text,
              onTap: () => editProfileField(title: 'Phone', controller: phone, keyboardType: TextInputType.phone, hint: '+234...')),
            const Divider(height: 1, indent: 58),
            profileRow(icon: Icons.wc_outlined, title: 'Gender', value: gender.text,
              onTap: chooseGender),
            const Divider(height: 1, indent: 58),
            profileRow(icon: Icons.location_on_outlined, title: 'Location', value: city.text,
              onTap: chooseState),
          ]),
        ),
        const SizedBox(height: 12),
        Material(
          color: OsColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: OsColors.border.withOpacity(.7)),
          ),
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.phone_iphone_outlined, color: OsColors.muted),
              value: phoneVisible,
              onChanged: (value) => setState(() => phoneVisible = value),
              title: const Text('Share phone number', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Let other OS members see your number', style: TextStyle(color: OsColors.muted, fontSize: 12)),
            ),
            const Divider(height: 1, indent: 58),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined, color: OsColors.muted),
              value: hidden,
              onChanged: (value) => setState(() => hidden = value),
              title: const Text('Hide profile photo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Control whether other members can see your photo', style: TextStyle(color: OsColors.muted, fontSize: 12)),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        OsButton(
          icon: Icons.check_rounded,
          label: saving ? 'Saving changesâ€¦' : 'Save changes',
          busy: saving,
          height: 56,
          onPressed: save,
        ),
        sectionLabel('Account'),
        Material(
          color: OsColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: OsColors.border.withOpacity(.7)),
          ),
          child: Column(children: [
            // Admins have no member e-mail verification step.
            if (!isAdminUser(u)) ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              leading: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: OsColors.surface2, borderRadius: BorderRadius.circular(13)),
                child: Icon(u['email_verified'] == true ? Icons.verified_user_outlined : Icons.mark_email_unread_outlined, color: OsColors.muted),
              ),
              title: Text(u['email_verified'] == true ? 'Email verified' : 'Verify your email', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Padding(padding: const EdgeInsets.only(top: 3), child: Text((u['email'] ?? '').toString(), style: const TextStyle(color: OsColors.muted, fontSize: 12))),
              trailing: u['email_verified'] == true
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : const Icon(Icons.chevron_right_rounded),
              onTap: u['email_verified'] == true ? null : verifyEmail,
            ),
            if (hasPhoto) ...[
              const Divider(height: 1, indent: 72),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1),
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: OsColors.surface2, borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.hide_image_outlined, color: OsColors.muted),
                ),
                title: const Text('Remove profile photo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Use the default avatar instead', style: TextStyle(color: OsColors.muted, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: removePhoto,
              ),
            ],
          ]),
        ),
        sectionLabel('Safety'),
        const Text('Never send money to someone you have only met online. Do not share passwords, private verification photos, or sensitive personal information.',
          style: TextStyle(color: OsColors.muted, height: 1.45)),
      ],
    );
  }
}

// ============================================================
// AVATAR
// ============================================================

class AvatarPhoto extends StatefulWidget {
  final Map<String, dynamic> user;
  final double radius;

  const AvatarPhoto({
    super.key,
    required this.user,
    required this.radius,
  });

  @override
  State<AvatarPhoto> createState() => _AvatarPhotoState();
}

class _AvatarPhotoState extends State<AvatarPhoto> {
  String? url;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    loadPhoto();
  }

  @override
  void didUpdateWidget(covariant AvatarPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user['profile_photo_key'] !=
        widget.user['profile_photo_key']) {
      url = null;
      failed = false;
      loadPhoto();
    }
  }

  Future<void> loadPhoto() async {
    final key = '${widget.user['profile_photo_key'] ?? ''}';
    if (key.isEmpty || key == 'null') return;

    try {
      final ownerId = int.tryParse('${widget.user['id'] ?? ''}') ?? 0;
      // The backend returns the approved original or a safe blurred derivative
      // depending on this viewer's reveal approval. This also covers chat and
      // connection avatars that don't carry a reveal-status field.
      final isOtherMember = ownerId > 0 && '$ownerId' != currentUserId;
      // Admin (OS Support) photos are never blurred for anyone, and admins
      // always see members' real photos.
      final ownerIsAdmin = widget.user['is_admin'] == true || isAdminUser(widget.user);
      final result = isOtherMember && !currentUserIsAdmin && !ownerIsAdmin
          ? await Api.blurredProfileUrl(ownerId)
          : await Api.mediaUrl(key);
      if (!mounted) return;
      setState(() => url = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showFallback = url == null || failed || url!.trim().isEmpty;

    // OS's built-in default avatar: no initials or external image asset needed.
    // It appears whenever a user has not uploaded a photo or the photo cannot load.
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: OsColors.surface2,
      backgroundImage: showFallback ? null : NetworkImage(url!),
      child: showFallback
          ? Container(
              width: widget.radius * 2,
              height: widget.radius * 2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF302044), Color(0xFF1B1730)],
                ),
              ),
              child: Icon(
                Icons.person_rounded,
                size: widget.radius * 1.08,
                color: const Color(0xFFD2C3FF),
              ),
            )
          : null,
    );
  }
}

// ============================================================
// EMPTY STATE AND HELPERS
// ============================================================

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 26),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: OsColors.border.withValues(alpha: .7)),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  OsColors.purpleDeep.withValues(alpha: .35),
                  OsColors.coral.withValues(alpha: .25),
                ],
              ),
            ),
            child: Icon(icon, size: 34, color: OsColors.purple),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: OsColors.muted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> mapOf(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

String safeName(dynamic value) {
  final name = (value ?? 'OS Member').toString().trim();
  return name.isEmpty ? 'OS Member' : name;
}

// ============================================================
// PRESENCE HELPERS (online / last seen)
// ============================================================

DateTime? _lastSeenTime(Map<String, dynamic> p) {
  final raw = '${p['last_seen_at'] ?? ''}'.trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

bool isOnline(Map<String, dynamic> p) {
  if (p['is_online'] == true) return true;
  final t = _lastSeenTime(p);
  return t != null && DateTime.now().difference(t).inMinutes < 2;
}

String presenceText(Map<String, dynamic> p) {
  if (isOnline(p)) return 'Online';

  final serverText = '${p['last_seen_text'] ?? ''}'.trim();
  if (serverText.isNotEmpty) return serverText;

  final t = _lastSeenTime(p);
  if (t == null) return 'Offline';

  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Last seen just now';
  if (d.inMinutes < 60) return 'Last seen ${d.inMinutes}m ago';
  if (d.inHours < 24) return 'Last seen ${d.inHours}h ago';
  return 'Last seen ${d.inDays}d ago';
}



// ============================================================
// FULL-SCREEN PROFILE PHOTO + SMALL HELPERS
// ============================================================

/// Opens a profile picture edge to edge. Pinch to zoom, tap to show/hide
/// the controls, swipe back or tap the close button to leave.
Future<void> showProfilePhoto(
  BuildContext context,
  Map<String, dynamic> person,
) async {
  final key = '${person['profile_photo_key'] ?? ''}'.trim();
  if (key.isEmpty || key == 'null') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This member has no profile photo to show.')),
    );
    return;
  }
  final revealStatus = '${person['photo_reveal_status'] ?? 'approved'}';
  final ownerId = int.tryParse('${person['id'] ?? ''}') ?? 0;
  if (ownerId > 0 && '$ownerId' != currentUserId && revealStatus != 'approved' && !currentUserIsAdmin && !isAdminUser(person)) {
    await Navigator.push(context, MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ProtectedProfilePhotoViewer(ownerId: ownerId, name: safeName(person['display_name']), revealStatus: revealStatus)));
    return;
  }
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ProfilePhotoViewer(
        photoKey: key,
        name: safeName(person['display_name']),
      ),
    ),
  );
}

class ProfilePhotoViewer extends StatefulWidget {
  final String photoKey;
  final String name;
  const ProfilePhotoViewer({super.key, required this.photoKey, required this.name});

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  String? url;
  String? error;
  bool showControls = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Api.mediaUrl(widget.photoKey);
      if (!mounted) return;
      setState(() => url = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Could not load photo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => showControls = !showControls),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (error != null)
              Center(
                child: Text(error!, style: const TextStyle(color: Colors.white)),
              )
            else if (url == null)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else
              InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: SizedBox.expand(
                  child: Image.network(
                    url!,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
              ),
            if (showControls)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(children: [
                      IconButton(
                        tooltip: 'Close',
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Lagos Â· 12 km", "Lagos Â· <1 km", or just the city when no distance.
String distanceLabel(String city, dynamic distance) {
  final d = double.tryParse('${distance ?? ''}');
  if (d == null) return city;
  final text = d < 1 ? '<1 km' : (d < 10 ? '${d.toStringAsFixed(1)} km' : '${d.round()} km');
  return '$city Â· $text';
}

class BlurredProfileThumb extends StatefulWidget {
  final int ownerId; const BlurredProfileThumb({super.key, required this.ownerId});
  @override State<BlurredProfileThumb> createState() => _BlurredProfileThumbState();
}
class _BlurredProfileThumbState extends State<BlurredProfileThumb> { String? url; @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final value = await Api.blurredProfileUrl(widget.ownerId); if (mounted) setState(() => url = value); } catch (_) {} }
  @override Widget build(BuildContext context) => url == null ? Container(color: OsColors.surface2) : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: OsColors.surface2));
}


class ProtectedProfilePhotoViewer extends StatefulWidget {
  final int ownerId; final String name; final String revealStatus;
  const ProtectedProfilePhotoViewer({super.key, required this.ownerId, required this.name, required this.revealStatus});
  @override State<ProtectedProfilePhotoViewer> createState() => _ProtectedProfilePhotoViewerState();
}
class _ProtectedProfilePhotoViewerState extends State<ProtectedProfilePhotoViewer> { String? url; @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final value = await Api.blurredProfileUrl(widget.ownerId); if (mounted) setState(() => url = value); } catch (_) {} }
  Future<void> _request() async { try { await Api.requestPhotoReveal(widget.ownerId); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reveal request sent to the photo owner.'))); Navigator.pop(context); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e)))); } }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.name), foregroundColor: Colors.white), body: Stack(fit: StackFit.expand, children: [if (url != null) Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()), Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 52), const SizedBox(height: 12), Text(widget.revealStatus == 'pending' ? 'Request pending' : widget.revealStatus == 'rejected' ? 'The owner declined this request' : 'This photo is protected', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)), if (widget.revealStatus != 'pending' && widget.revealStatus != 'rejected') Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(onPressed: _request, icon: const Icon(Icons.visibility_outlined), label: const Text('Request reveal')))]))]));
}


class _OsFeatureTourDialog extends StatefulWidget {
  const _OsFeatureTourDialog();

  @override
  State<_OsFeatureTourDialog> createState() => _OsFeatureTourDialogState();
}

class _OsFeatureTourDialogState extends State<_OsFeatureTourDialog> {
  final PageController _pages = PageController();
  int _index = 0;

  static const _slides = <_OsTourSlide>[
    _OsTourSlide(
      eyebrow: 'WELCOME TO OS',
      title: 'Real people. Real intentions.',
      body: 'Meet people with more confidence through a community built around authenticity and respectful connections.',
      icon: Icons.diversity_3_rounded,
      accent: Color(0xFFFF80AB),
      floating: [Icons.favorite_rounded, Icons.chat_bubble_rounded, Icons.auto_awesome_rounded],
      scene: CartoonScene.discover,
    ),
    _OsTourSlide(
      eyebrow: 'TRUST FIRST',
      title: 'Your privacy stays yours.',
      body: 'Look for verification badges, manage who can find you, and approve photo reveal requests on your terms.',
      icon: Icons.shield_moon_rounded,
      accent: Color(0xFF9C8CFF),
      floating: [Icons.verified_rounded, Icons.visibility_rounded, Icons.lock_rounded],
      scene: CartoonScene.verified,
    ),
    _OsTourSlide(
      eyebrow: 'MAKE IT A CONVERSATION',
      title: 'Chat your way.',
      body: 'Reply to a specific message, react to the moment, share voice notes where available, and call when you are ready.',
      icon: Icons.forum_rounded,
      accent: Color(0xFF69D6C4),
      floating: [Icons.mic_rounded, Icons.reply_rounded, Icons.call_rounded],
      scene: CartoonScene.chat,
    ),
    _OsTourSlide(
      eyebrow: 'YOU ARE IN CONTROL',
      title: 'Explore at your pace.',
      body: 'Discover people, set your dating preferences, control contact visibility, and use block or report tools whenever needed.',
      icon: Icons.explore_rounded,
      accent: Color(0xFFFFC36B),
      floating: [Icons.tune_rounded, Icons.location_on_rounded, Icons.health_and_safety_rounded],
      scene: CartoonScene.safety,
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('os_feature_tour_seen_v1', true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_index];
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: OsColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: screen.height * .88),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: screen.height < 700 ? 180 : 218,
            child: PageView.builder(
              controller: _pages,
              itemCount: _slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => _TourArtwork(slide: _slides[i]),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(slide.eyebrow, style: const TextStyle(color: OsColors.purple, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(height: 7),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(slide.title, key: ValueKey(slide.title), style: const TextStyle(fontSize: 24, height: 1.08, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text(slide.body, key: ValueKey(slide.body), style: const TextStyle(color: OsColors.muted, fontSize: 13, height: 1.5)),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  ...List.generate(_slides.length, (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.only(right: 6),
                    width: i == _index ? 23 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: i == _index ? OsColors.purple : OsColors.muted.withValues(alpha: .3), borderRadius: BorderRadius.circular(20)),
                  )),
                  const Spacer(),
                  Text('${_index + 1} of ${_slides.length}', style: const TextStyle(color: OsColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 18),
                Row(children: [
                  if (_index > 0)
                    IconButton.filledTonal(onPressed: () => _pages.previousPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic), icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Previous feature'),
                  if (_index > 0) const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    onPressed: () {
                      if (_index < _slides.length - 1) {
                        _pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
                      } else {
                        _finish();
                      }
                    },
                    icon: Icon(_index == _slides.length - 1 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded),
                    label: Text(_index == _slides.length - 1 ? 'Letâ€™s explore OS' : 'Next feature'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  )),
                ]),
                Center(child: TextButton(onPressed: _finish, child: Text(_index == _slides.length - 1 ? 'Close tour' : 'Maybe later'))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _OsTourSlide {
  final String eyebrow;
  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final List<IconData> floating;
  final CartoonScene scene;
  const _OsTourSlide({required this.eyebrow, required this.title, required this.body, required this.icon, required this.accent, required this.floating, required this.scene});
}

class _TourArtwork extends StatelessWidget {
  final _OsTourSlide slide;
  const _TourArtwork({required this.slide});

  @override
  Widget build(BuildContext context) =>
      CartoonSceneView(scene: slide.scene, borderRadius: BorderRadius.zero);
}

