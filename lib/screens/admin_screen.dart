import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';
import '../theme/os_layout.dart';
import '../theme/user_badge.dart';
import 'chat_screen.dart';
import 'call_screen.dart';

String mimeForPath(String path, {required bool video}) {
  final lower = path.toLowerCase();
  if (video) {
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'video/mp4';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

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
      final result = await Api.mediaUrl(key);
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 38, color: OsColors.purple),
          const SizedBox(height: 10),
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
// ADMIN DASHBOARD (only shown when user['is_admin'] == true)
// ============================================================

String agoText(String? iso) {
  final t = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// Standalone admin entry point used by main.dart. Admins get only the
/// administration interface, not the member Discover/Profile shell.
class AdminScreen extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  const AdminScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) => AdminDashboardScreen(
        user: user,
        onLogout: onLogout,
      );
}

class AdminDashboardScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  const AdminDashboardScreen({
    super.key,
    required this.user,
    required this.onLogout,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int section = 0;
  bool loading = true;
  bool loadingMembers = false;
  bool loadingReports = false;
  String? error;
  String? membersError;
  String? reportsError;
  Map<String, dynamic> counts = {};
  Map<String, dynamic> adminUser = {};
  String memberFilter = 'all';
  bool uploadingAdminPhoto = false;
  List<dynamic> pending = [];
  List<dynamic> members = [];
  List<dynamic> reports = [];
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Use the authenticated user immediately; GET /me refreshes it in the
    // background so the header never defaults to a hard-coded OS Admin label.
    adminUser = Map<String, dynamic>.from(widget.user);
    load();
    loadAdminUser();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadAdminUser() async {
    try {
      final user = await Api.me();
      if (mounted) setState(() => adminUser = {...adminUser, ...user});
    } catch (_) {
      // Dashboard data remains usable if the profile endpoint is unavailable.
    }
  }

  Future<void> changeAdminPhoto() async {
    if (uploadingAdminPhoto) return;
    try {
      final selected = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88);
      if (selected == null || !mounted) return;
      setState(() => uploadingAdminPhoto = true);
      final uploaded = await Api.upload(File(selected.path), 'profile', selected.mimeType ?? mimeForPath(selected.path, video: false));
      final key = (uploaded['object_key'] ?? uploaded['key'])?.toString();
      if (key == null || key.isEmpty) throw Exception('Upload did not return a photo key.');
      final updated = await Api.profile({'profile_photo_key': key});
      if (!mounted) return;
      setState(() { adminUser = {...adminUser, ...updated, 'profile_photo_key': key}; uploadingAdminPhoto = false; });
      toast('Admin profile photo updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => uploadingAdminPhoto = false);
      toast('Could not update admin photo. ${Api.friendlyError(e)}');
    }
  }

  Future<int> _openMemberConversation(Map<String, dynamic> member) async {
    final memberId = int.tryParse('${member['id'] ?? member['user_id'] ?? ''}');
    if (memberId == null || memberId <= 0) throw Exception('This member has no valid user ID.');
    final conversation = await Api.openConversation(memberId);
    final id = int.tryParse('${conversation['id'] ?? conversation['conversation_id'] ?? ''}');
    if (id == null || id <= 0) throw Exception('The server did not return a conversation ID.');
    return id;
  }

  Future<void> chatWithMember(Map<String, dynamic> member) async {
    try {
      final conversationId = await _openMemberConversation(member);
      final myId = adminUser['id'];
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChatScreen(
        conversationId: conversationId,
        person: member,
        myId: myId,
      )));
    } catch (e) { toast('Could not open chat. ${Api.friendlyError(e)}'); }
  }

  Future<void> callMember(Map<String, dynamic> member, {required bool video}) async {
    try {
      final conversationId = await _openMemberConversation(member);
      final call = await Api.inviteCall(conversationId, video: video);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => LiveCallScreen(call: call, isCaller: true)));
    } catch (e) { toast('Could not start call. ${Api.friendlyError(e)}'); }
  }

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result = mapOf(await Api.request('GET', '/admin/dashboard'));
      if (!mounted) return;
      setState(() {
        counts = mapOf(result['counts']);
        pending = (result['pending'] as List?) ?? [];
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = '$e';
      });
    }
  }

  Future<void> loadMembers({String? query}) async {
    setState(() {
      loadingMembers = true;
      membersError = null;
    });
    try {
      final q = (query ?? searchController.text).trim();
      final path = q.isEmpty ? '/admin/users' : '/admin/users?search=${Uri.encodeQueryComponent(q)}';
      final result = await Api.list(path);
      if (!mounted) return;
      setState(() {
        members = result;
        loadingMembers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        membersError = '$e';
        loadingMembers = false;
      });
    }
  }

  Future<void> loadReports() async {
    setState(() {
      loadingReports = true;
      reportsError = null;
    });
    try {
      final result = await Api.adminReports();
      if (!mounted) return;
      setState(() {
        reports = result;
        loadingReports = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        reportsError = '$e';
        loadingReports = false;
      });
    }
  }

  Future<void> chooseSection(int next) async {
    setState(() => section = next);
    if (next == 2 && members.isEmpty && !loadingMembers) await loadMembers();
    if (next == 3 && reports.isEmpty && !loadingReports) await loadReports();
  }

  Future<void> openReview(dynamic raw) async {
    final reviewed = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => AdminReviewScreen(submission: mapOf(raw)),
      ),
    );
    if (reviewed != null) {
      toast(reviewed);
      await load();
    }
  }

  Widget stat(String label, dynamic value, IconData icon, {Color? color}) {
    final target = label == 'Pending' ? 1 : (label == 'Reports' ? 3 : (label == 'Members' || label == 'Verified' || label == 'Suspended' || label == 'New today' ? 2 : 0));
    return SizedBox.expand(
      child: Material(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => chooseSection(target),
          child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, color: color ?? OsColors.purple, size: 22),
            const SizedBox(height: 6),
            Text('${value ?? 0}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: OsColors.muted, fontSize: 11)),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget sectionButton(int index, String label, IconData icon) {
    final selected = section == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, size: 17, color: selected ? Colors.white : OsColors.purple),
        label: Text(label),
        selected: selected,
        onSelected: (_) => chooseSection(index),
      ),
    );
  }

  Future<void> composeMessage({bool announcement = false, int? recipientUserId, String? recipientName}) async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    final recipientController = TextEditingController(text: recipientUserId?.toString() ?? '');
    String audience = recipientUserId == null ? 'all' : 'user';
    bool sending = false;
    try {
      final sent = await showDialog<bool>(
        context: context,
        barrierDismissible: !sending,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(announcement ? 'New announcement' : recipientName == null ? 'Send a message' : 'Message $recipientName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!announcement) ...[
                    DropdownButtonFormField<String>(
                      value: audience,
                      decoration: const InputDecoration(labelText: 'Recipient'),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All members (broadcast)')),
                        DropdownMenuItem(value: 'user', child: Text('One member by user ID')),
                      ],
                      onChanged: sending ? null : (v) => setDialogState(() => audience = v ?? 'all'),
                    ),
                    if (audience == 'user')
                      TextField(controller: recipientController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Member user ID')),
                  ],
                  TextField(controller: titleController, maxLength: 100, decoration: InputDecoration(labelText: announcement ? 'Announcement title' : 'Subject')),
                  TextField(controller: bodyController, minLines: 4, maxLines: 7, maxLength: 2000, decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true)),
                  const SizedBox(height: 8),
                  const Text('Messages are sent through the admin API. If the server does not support this action yet, it will report that instead of pretending it was sent.', style: TextStyle(fontSize: 12, color: OsColors.muted)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: sending ? null : () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: sending ? null : () async {
                  final title = titleController.text.trim();
                  final body = bodyController.text.trim();
                  final recipientId = int.tryParse(recipientController.text.trim());
                  if (title.isEmpty || body.isEmpty) {
                    toast('Enter a subject/title and message.');
                    return;
                  }
                  if (!announcement && audience == 'user' && (recipientId == null || recipientId <= 0)) {
                    toast('Enter a valid member user ID.');
                    return;
                  }
                  setDialogState(() => sending = true);
                  try {
                    if (announcement) {
                      await Api.request('POST', '/admin/announcements', body: {'title': title, 'body': body, 'audience': 'all'});
                    } else {
                      await Api.request('POST', '/admin/messages', body: {
                        'subject': title,
                        'body': body,
                        'recipient_type': audience,
                        if (audience == 'user') 'recipient_user_id': recipientId,
                      });
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                  } catch (e) {
                    setDialogState(() => sending = false);
                    toast('Could not send. ${Api.friendlyError(e)}');
                  }
                },
                icon: sending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                label: Text(sending ? 'Sending…' : 'Send'),
              ),
            ],
          ),
        ),
      );
      if (sent == true) toast(announcement ? 'Announcement sent.' : 'Message sent.');
    } finally {
      titleController.dispose();
      bodyController.dispose();
      recipientController.dispose();
    }
  }

  Future<void> suspendMember(Map<String, dynamic> member) async {
    final id = int.tryParse('${member['id'] ?? member['user_id'] ?? ''}');
    if (id == null || id <= 0) {
      toast('This member record has no valid user ID.');
      return;
    }
    final name = safeName(member['display_name'] ?? member['name']);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspend member?'),
        content: Text('Suspend $name? They may lose access to their account. This action will be sent to the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Suspend')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Api.suspend(id);
      toast('$name suspended.');
      await loadMembers();
      await load();
    } catch (e) {
      toast('Could not suspend member. ${Api.friendlyError(e)}');
    }
  }

  Widget dashboardContent() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Platform overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisExtent: 120,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        children: [
          stat('Pending', counts['pending'], Icons.hourglass_top),
          stat('Verified', counts['verified_users'], Icons.verified_outlined, color: Colors.green),
          stat('Members', counts['total_users'], Icons.people_outline),
          stat('Reports', counts['open_reports'] ?? reports.length, Icons.flag_outlined, color: Colors.deepOrange),
          stat('Suspended', counts['suspended_users'], Icons.gpp_bad_outlined, color: Colors.red),
          stat('New today', counts['new_users_today'], Icons.person_add_alt_1_outlined),
        ],
      ),
      const SizedBox(height: 22),
      const Text('Admin tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisExtent: 136,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        children: [
          _toolCard('Send a message', 'Broadcast or contact a member', Icons.mark_email_unread_outlined, () => composeMessage()),
          _toolCard('Announcement', 'Post an app-wide notice', Icons.campaign_outlined, () => composeMessage(announcement: true)),
          _toolCard('Manage members', 'Search and suspend accounts', Icons.manage_accounts_outlined, () => chooseSection(2)),
          _toolCard('Safety reports', 'Review member reports', Icons.shield_outlined, () => chooseSection(3)),
        ],
      ),
      const SizedBox(height: 22),
      Row(children: [
        const Expanded(child: Text('Pending verifications', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
        TextButton(onPressed: () => chooseSection(1), child: const Text('View all')),
      ]),
      if (pending.isEmpty)
        const EmptyState(icon: Icons.task_alt, title: 'No pending verifications', text: 'New submissions will appear here for review.')
      else
        ...pending.take(5).map((raw) => _verificationCard(mapOf(raw))),
    ]);
  }

  Widget _toolCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return Material(
      color: OsColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: OsColors.purple, size: 25),
            const SizedBox(height: 8),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: OsColors.muted)),
          ]),
        ),
      ),
    );
  }

  Widget _verificationCard(Map<String, dynamic> item) {
    final person = mapOf(item['user']);
    final city = '${person['city'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: OsColors.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: AvatarPhoto(user: person, radius: 25),
        title: Text(safeName(person['display_name']), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text([if (city.isNotEmpty) city, 'Submitted ${agoText(item['created_at']?.toString())}'].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openReview(item),
      ),
    );
  }

  Widget verificationsContent() {
    if (loading) return const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()));
    if (error != null) return EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load verifications', text: error!);
    if (pending.isEmpty) return const EmptyState(icon: Icons.task_alt, title: 'All caught up', text: 'There are no verification requests waiting for review.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Identity verification queue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text('${pending.length} submission(s) waiting for review', style: const TextStyle(color: OsColors.muted)),
      const SizedBox(height: 12),
      ...pending.map((raw) => _verificationCard(mapOf(raw))),
    ]);
  }

  Widget membersContent() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Member management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      TextField(
        controller: searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (value) => loadMembers(query: value),
        decoration: InputDecoration(
          hintText: 'Search name, email or member ID',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: () => loadMembers()),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        ChoiceChip(label: const Text('All'), selected: memberFilter == 'all', onSelected: (_) => setState(() => memberFilter = 'all')),
        ChoiceChip(label: const Text('Verified'), selected: memberFilter == 'verified', onSelected: (_) => setState(() => memberFilter = 'verified')),
        ChoiceChip(label: const Text('Not verified'), selected: memberFilter == 'unverified', onSelected: (_) => setState(() => memberFilter = 'unverified')),
        ChoiceChip(label: const Text('Suspended'), selected: memberFilter == 'suspended', onSelected: (_) => setState(() => memberFilter = 'suspended')),
      ]),
      const SizedBox(height: 12),
      if (loadingMembers) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (membersError != null) EmptyState(icon: Icons.cloud_off, title: 'Could not load members', text: membersError!)
      else if (members.isEmpty) const EmptyState(icon: Icons.people_outline, title: 'No members to show', text: 'Search for a member or refresh the list. The admin API must provide GET /admin/users.')
      else ...members.map((raw) => mapOf(raw)).where((member) {
        final verified = member['is_verified'] == true || member['verified'] == true || member['verification_status'] == 'verified';
        final suspended = member['is_suspended'] == true || member['status'] == 'suspended';
        if (memberFilter == 'verified') return verified;
        if (memberFilter == 'unverified') return !verified;
        if (memberFilter == 'suspended') return suspended;
        return true;
      }).map((member) {
        final name = safeName(member['display_name'] ?? member['name']);
        final email = '${member['email'] ?? 'No email supplied'}';
        final id = member['id'] ?? member['user_id'] ?? '—';
        final suspended = member['is_suspended'] == true || member['status'] == 'suspended';
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(color: OsColors.surface, borderRadius: BorderRadius.circular(17)),
          child: ListTile(
            leading: AvatarPhoto(user: member, radius: 23),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('$email\nID: $id · ${suspended ? 'Suspended' : 'Active'} · ${(member['is_verified'] == true || member['verified'] == true || member['verification_status'] == 'verified') ? 'Verified' : 'Not verified'}', maxLines: 3, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'chat') chatWithMember(member);
                if (value == 'audio') callMember(member, video: false);
                if (value == 'video') callMember(member, video: true);
                if (value == 'suspend') suspendMember(member);
                if (value == 'message') {
                  final memberId = int.tryParse('${member['id'] ?? member['user_id'] ?? ''}');
                  if (memberId == null || memberId <= 0) {
                    toast('This member record has no valid user ID.');
                  } else {
                    composeMessage(recipientUserId: memberId, recipientName: name);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'chat', child: ListTile(leading: Icon(Icons.chat_bubble_outline), title: Text('Open chat'))),
                PopupMenuItem(value: 'audio', child: ListTile(leading: Icon(Icons.call_outlined), title: Text('Audio call'))),
                PopupMenuItem(value: 'video', child: ListTile(leading: Icon(Icons.videocam_outlined), title: Text('Video call'))),
                PopupMenuItem(value: 'message', child: ListTile(leading: Icon(Icons.message_outlined), title: Text('Send admin message'))),
                PopupMenuItem(value: 'suspend', child: ListTile(leading: Icon(Icons.block), title: Text('Suspend member'))),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  Widget reportsContent() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Safety & reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        IconButton(tooltip: 'Refresh reports', onPressed: loadingReports ? null : loadReports, icon: const Icon(Icons.refresh)),
      ]),
      const Text('Review reported accounts and take moderation action.', style: TextStyle(color: OsColors.muted)),
      const SizedBox(height: 12),
      if (loadingReports) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (reportsError != null) EmptyState(icon: Icons.cloud_off, title: 'Could not load reports', text: reportsError!)
      else if (reports.isEmpty) const EmptyState(icon: Icons.verified_user_outlined, title: 'No reports returned', text: 'There are no reports to display, or the admin reports endpoint returned an empty list.')
      else ...reports.map((raw) {
        final report = mapOf(raw);
        final reporter = mapOf(report['reporter'] ?? report['reported_by_user']);
        final reported = mapOf(report['reported_user'] ?? report['user']);
        final reason = '${report['reason'] ?? report['description'] ?? 'No reason provided'}';
        final id = report['id'] ?? report['report_id'] ?? '—';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: OsColors.surface, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.flag_outlined, color: Colors.deepOrange), const SizedBox(width: 8), Expanded(child: Text('Report #$id', style: const TextStyle(fontWeight: FontWeight.w900))), Text('${report['status'] ?? 'Open'}', style: const TextStyle(color: OsColors.muted, fontSize: 12))]),
            const SizedBox(height: 8),
            Text('Reported member: ${safeName(reported['display_name'] ?? reported['name'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('By: ${safeName(reporter['display_name'] ?? reporter['name'])}', style: const TextStyle(color: OsColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Text(reason),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(onPressed: () => suspendMember(reported), icon: const Icon(Icons.block), label: const Text('Suspend reported member'))),
          ]),
        );
      }),
    ]);
  }

  Widget _header() => Row(children: [
        GestureDetector(
          onTap: changeAdminPhoto,
          child: Stack(alignment: Alignment.bottomRight, children: [
            // Admin photo is never blurred or hidden.
            AvatarPhoto(user: adminUser, radius: 25),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: OsColors.purple, shape: BoxShape.circle),
              child: Icon(uploadingAdminPhoto ? Icons.hourglass_top : Icons.camera_alt, size: 12, color: Colors.white),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              safeName(adminUser['display_name'] ?? adminUser['full_name'] ?? adminUser['name'] ?? adminUser['email'] ?? 'Administrator'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            Row(children: [
              const Icon(Icons.verified, size: 15, color: kAdminGold),
              const SizedBox(width: 5),
              const Text('OS Admin', style: TextStyle(color: kAdminGold, fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('Tap photo to change',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OsColors.muted, fontSize: 12)),
              ),
            ]),
          ]),
        ),
        IconButton(tooltip: 'Refresh', onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'Log out', onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
      ]);

  Widget _sectionBody() {
    if (section == 0) {
      if (loading && counts.isEmpty) {
        return const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()));
      }
      if (error != null && counts.isEmpty) {
        return EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load the dashboard', text: error!);
      }
      return dashboardContent();
    }
    if (section == 1) return verificationsContent();
    if (section == 2) return membersContent();
    return reportsContent();
  }

  @override
  Widget build(BuildContext context) {
    final wide = OsBreakpoints.isWide(context);
    final pendingCount = int.tryParse('${counts['pending'] ?? 0}') ?? 0;
    final reportCount = int.tryParse('${counts['open_reports'] ?? 0}') ?? 0;

    Widget badge(int n, Widget icon) =>
        Badge(isLabelVisible: n > 0, label: Text('$n'), backgroundColor: OsColors.coral, child: icon);

    final list = RefreshIndicator(
      onRefresh: () async {
        await load();
        if (section == 2) await loadMembers();
        if (section == 3) await loadReports();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _header(),
          const SizedBox(height: 18),
          _sectionBody(),
        ],
      ),
    );
    final main = ResponsiveBody(maxWidth: 1000, child: list);

    // Scaffold supplies the Material ancestor that chips and tiles need.
    return Scaffold(
      backgroundColor: OsColors.bg,
      body: SafeArea(
        child: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: section,
                  onDestinationSelected: chooseSection,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: OsColors.surface,
                  destinations: [
                    const NavigationRailDestination(
                        icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Overview')),
                    NavigationRailDestination(
                        icon: badge(pendingCount, const Icon(Icons.verified_user_outlined)),
                        selectedIcon: badge(pendingCount, const Icon(Icons.verified_user)),
                        label: const Text('Verify')),
                    const NavigationRailDestination(
                        icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Members')),
                    NavigationRailDestination(
                        icon: badge(reportCount, const Icon(Icons.shield_outlined)),
                        selectedIcon: badge(reportCount, const Icon(Icons.shield)),
                        label: const Text('Reports')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: main),
              ])
            : main,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: section,
              onDestinationSelected: chooseSection,
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
                NavigationDestination(
                    icon: badge(pendingCount, const Icon(Icons.verified_user_outlined)),
                    selectedIcon: badge(pendingCount, const Icon(Icons.verified_user)),
                    label: 'Verify'),
                const NavigationDestination(
                    icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Members'),
                NavigationDestination(
                    icon: badge(reportCount, const Icon(Icons.shield_outlined)),
                    selectedIcon: badge(reportCount, const Icon(Icons.shield)),
                    label: 'Reports'),
              ],
            ),
    );
  }
}

class AdminReviewScreen extends StatefulWidget {
  final Map<String, dynamic> submission;

  const AdminReviewScreen({super.key, required this.submission});

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  final noteController = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    noteController.dispose();
    super.dispose();
  }

  void toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> decide(String decision) async {
    if (busy) return;

    final note = noteController.text.trim();
    if (decision != 'verified' && note.isEmpty) {
      toast('Add a note so the member knows what to fix.');
      return;
    }

    final id = int.tryParse('${widget.submission['id']}');
    if (id == null) {
      toast('Invalid submission.');
      return;
    }

    setState(() => busy = true);

    try {
      await Api.request(
        'POST',
        '/admin/verifications/$id/review',
        body: {'decision': decision, 'note': note},
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        switch (decision) {
          'verified' => 'Member verified.',
          'rejected' => 'Verification rejected.',
          _ => 'Re-verification requested.',
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      toast('Could not submit the review. ${Api.friendlyError(e)}');
    }
  }

  Widget label(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget media(String key) {
    if (key.trim().isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: OsColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          'Not provided',
          style: TextStyle(color: OsColors.muted),
        ),
      );
    }
    return AdminMediaPreview(keyValue: key);
  }

  @override
  Widget build(BuildContext context) {
    final person = mapOf(widget.submission['user']);
    final name = safeName(person['display_name']);
    final comparisonKey =
        '${widget.submission['comparison_photo_key'] ?? ''}'.trim();
    final livenessKey =
        '${widget.submission['liveness_media_key'] ?? ''}'.trim();
    final currentPhotoKey = '${person['profile_photo_key'] ?? ''}'.trim();
    final photoChanged =
        currentPhotoKey.isNotEmpty && currentPhotoKey != comparisonKey;
    final bio = '${person['bio'] ?? ''}'.trim();

    final details = [
      if ('${person['city'] ?? ''}'.trim().isNotEmpty) '${person['city']}',
      if ('${person['gender'] ?? ''}'.trim().isNotEmpty) '${person['gender']}',
      if ('${person['date_of_birth'] ?? ''}'.trim().isNotEmpty)
        'Born ${person['date_of_birth']}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('Review verification')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          if (busy) const LinearProgressIndicator(),
          const SizedBox(height: 10),
          Row(
            children: [
              AvatarPhoto(user: person, radius: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(
                        details,
                        style: const TextStyle(
                          color: OsColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    Text(
                      'Submitted ${agoText(widget.submission['created_at']?.toString())}',
                      style: const TextStyle(
                        color: OsColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OsColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(bio, style: const TextStyle(height: 1.4)),
            ),
          ],
          if (photoChanged) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The profile photo was changed after this '
                      'verification was submitted.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          label('Photo submitted for comparison'),
          media(comparisonKey),
          if (photoChanged) ...[
            label('Current profile photo'),
            media(currentPhotoKey),
          ],
          label('Liveness check'),
          media(livenessKey),
          label('Note to the member'),
          TextField(
            controller: noteController,
            enabled: !busy,
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Required to reject or ask for re-verification. '
                  'Optional when approving.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : () => decide('verified'),
            icon: const Icon(Icons.verified),
            label: const Text('Approve'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: busy ? null : () => decide('reverify'),
            icon: const Icon(Icons.refresh),
            label: const Text('Ask for re-verification'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
            onPressed: busy ? null : () => decide('rejected'),
            icon: const Icon(Icons.close),
            label: const Text('Reject'),
          ),
        ],
      ),
    );
  }
}

class AdminMediaPreview extends StatefulWidget {
  final String keyValue;
  const AdminMediaPreview({super.key, required this.keyValue});
  @override
  State<AdminMediaPreview> createState() => _AdminMediaPreviewState();
}

class _AdminMediaPreviewState extends State<AdminMediaPreview> {
  String? url;
  String? error;
  VideoPlayerController? video;
  bool initializingVideo = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final value = await Api.mediaUrl(widget.keyValue);
      if (!mounted) return;
      // Liveness media is often a video; try video playback first, then fall back to image.
      final controller = VideoPlayerController.networkUrl(Uri.parse(value));
      try {
        setState(() { url = value; initializingVideo = true; });
        await controller.initialize().timeout(const Duration(seconds: 8));
        if (!mounted) { await controller.dispose(); return; }
        setState(() { video = controller; initializingVideo = false; });
      } catch (_) {
        await controller.dispose();
        if (!mounted) return;
        setState(() { url = value; initializingVideo = false; });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load submitted media.');
    }
  }

  @override
  void dispose() { video?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (error != null) return Text(error!, style: const TextStyle(color: OsColors.muted));
    if (url == null || initializingVideo) return const SizedBox(height: 130, child: Center(child: CircularProgressIndicator()));
    if (video != null && video!.value.isInitialized) {
      return Column(children: [
        ClipRRect(borderRadius: BorderRadius.circular(14), child: AspectRatio(aspectRatio: video!.value.aspectRatio > 0 ? video!.value.aspectRatio : 16 / 9, child: VideoPlayer(video!))),
        TextButton.icon(onPressed: () async { if (video!.value.isPlaying) { await video!.pause(); } else { await video!.play(); } if (mounted) setState(() {}); }, icon: Icon(video!.value.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(video!.value.isPlaying ? 'Pause video' : 'Play video')),
      ]);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(url!, height: 220, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(16), child: Text('Unable to display submitted media.'))));
  }
}