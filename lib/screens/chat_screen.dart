import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api.dart';
import '../theme/os_layout.dart';
import '../theme/app_theme.dart';
import '../theme/user_badge.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final int conversationId;
  final Map<String, dynamic> person;
  final dynamic myId;
  /// Lets the app shell open its canonical public-profile screen without
  /// coupling this chat screen to app_shell.dart.
  final Widget Function(int userId, Map<String, dynamic> profile)? profileBuilder;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.person,
    this.myId,
    this.profileBuilder,
  });

  @override
  State<ChatScreen> createState() => _ChatState();
}

class _ChatState extends State<ChatScreen> {
  List<dynamic> ms = [];
  Timer? timer;
  final input = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;
  bool loaded = false;
  bool hasText = false;
  int? expirySeconds; // null means keep indefinitely
  bool otherTyping = false;
  Map? replyingTo;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    input.addListener(() {
      final v = input.text.trim().isNotEmpty;
      if (v != hasText) setState(() => hasText = v);
      final now = DateTime.now();
      if (now.difference(_lastTypingSent).inSeconds >= 2) {
        _lastTypingSent = now;
        Api.typing(widget.conversationId, v).catchError((_) {});
      }
    });
    load();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool _mine(Map m) {
    if (m['mine'] is bool) return m['mine'] as bool;
    if (m['is_mine'] is bool) return m['is_mine'] as bool;
    final sender = m['sender_id'];
    if (sender != null && widget.myId != null) return sender == widget.myId;
    if (sender != null) return sender != widget.person['id'];
    return true;
  }

  Future<void> load() async {
    try {
      final x = await Api.messages(widget.conversationId);
      if (!mounted) return;
      if (x.any((raw) => raw is Map && !_mine(raw) && raw['read_at'] == null)) {
        Api.markConversationRead(widget.conversationId).catchError((_) {});
      }
      final wasLoaded = loaded;
      final previousCount = ms.length;
      final grew = x.length != previousCount;
      bool typing = false;
      try { typing = await Api.otherPersonTyping(widget.conversationId); } catch (_) {}
      if (!mounted) return;
      setState(() {
        ms = x;
        loaded = true;
        otherTyping = typing;
      });
      if (grew && wasLoaded && x.length > previousCount && x.isNotEmpty) {
        final last = x.last;
        if (last is Map && !_mine(last)) SystemSound.play(SystemSoundType.alert);
      }
      if (grew) _toBottom();
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      await Api.sendMessage(widget.person['id'], text, expiresInSeconds: expirySeconds, replyToMessageId: int.tryParse('${replyingTo?['id'] ?? ''}'));
      if (mounted) setState(() => replyingTo = null);
      Api.typing(widget.conversationId, false).catchError((_) {});
      SystemSound.play(SystemSoundType.click);
      input.clear();
      await load();
      _toBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e))));
      }
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _clearChat() async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Clear chat for you?'), content: const Text('Messages will be hidden from your account only. The other person keeps their copy.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear chat'))]));
    if (ok != true) return;
    try { await Api.clearConversationForMe(widget.conversationId); await load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e)))); }
  }

  Future<void> _launchContact(String action) async {
    final phone = (widget.person['phone_number'] ?? '').toString().trim();
    if (widget.person['phone_visible'] != true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This member has chosen not to share their phone number.')));
      return;
    }
    if (phone.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This person has not shared a contact number.')));
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = action == 'whatsapp'
        ? Uri.parse('https://wa.me/${digits.replaceAll('+', '')}')
        : Uri(scheme: 'tel', path: digits);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No compatible app was found.')));
    }
  }

  Future<void> _startCall({required bool video}) async {
    try {
      final call = await Api.inviteCall(widget.conversationId, video: video);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => LiveCallScreen(call: call, isCaller: true),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e))));
    }
  }

  Future<void> _openPersonProfile() async {
    final id = int.tryParse('${widget.person['id'] ?? ''}');
    if (id == null) return;
    final profile = await Api.userProfile(id);
    if (!mounted) return;
    final builder = widget.profileBuilder;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => builder == null
            ? _ChatPublicProfileRoute(user: profile)
            : builder(id, profile),
      ),
    );
  }

  Future<void> _report() async {
    final reasons = ['Harassment', 'Fake profile', 'Inappropriate content', 'Scam or spam'];
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Report this person',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          ),
          for (final r in reasons)
            ListTile(title: Text(r), onTap: () => Navigator.pop(s, r)),
        ]),
      ),
    );
    if (reason == null) return;
    try {
      await Api.report(widget.person['id'], reason);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report sent. Thank you.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e))));
    }
  }

  Future<void> _block() async {
    final name = (widget.person['display_name'] ?? 'this person').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OsColors.surface,
        title: Text('Block $name?'),
        content: const Text('They will no longer be able to message you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Block')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.block(widget.person['id']);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e))));
    }
  }

  /// Old status notifications were saved with a broken "??" prefix.
  String _cleanBody(String s) => s.replaceFirst(RegExp(r'^\?+\s*'), '');

  String _expiryLabel(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '$value';
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month} $hour:$minute';
  }

  Future<void> _messageActions(Map m) async {
    final id = int.tryParse('${m['id'] ?? ''}');
    if (id == null) return;
    final action = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Text('❤️', style: TextStyle(fontSize: 22)), title: const Text('Like message'), onTap: () => Navigator.pop(ctx, 'like')),
      ListTile(leading: const Icon(Icons.reply_rounded), title: const Text('Reply'), onTap: () => Navigator.pop(ctx, 'reply')),
      ListTile(leading: const Icon(Icons.timer_outlined), title: const Text('Set disappearing time for my copy'), onTap: () => Navigator.pop(ctx, 'retention')),
      ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete for me'), onTap: () => Navigator.pop(ctx, 'delete')),
    ])));
    if (action == null || !mounted) return;
    try {
      if (action == 'like') { await Api.reactToMessage(id, '❤️'); await load(); }
      if (action == 'delete') { await Api.deleteMessageForMe(id); await load(); }
      if (action == 'retention') {
        final choice = await showModalBottomSheet<dynamic>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: Wrap(children: [
          ListTile(title: const Text('Use sender’s timer'), onTap: () => Navigator.pop(ctx, 'inherit')),
          ListTile(title: const Text('Disappear after 1 hour on my side'), onTap: () => Navigator.pop(ctx, 3600)),
          ListTile(title: const Text('Disappear after 24 hours on my side'), onTap: () => Navigator.pop(ctx, 86400)),
          ListTile(title: const Text('Disappear after 7 days on my side'), onTap: () => Navigator.pop(ctx, 604800)),
          ListTile(title: const Text('Disappear after 30 days on my side'), onTap: () => Navigator.pop(ctx, 2592000)),
          ListTile(title: const Text('Keep my copy indefinitely'), onTap: () => Navigator.pop(ctx, 'indefinite')),
        ])));
        if (choice == 'inherit') { await Api.setMessageRetention(id, 'inherit'); await load(); }
        else if (choice == 'indefinite') { await Api.setMessageRetention(id, null); await load(); }
        else if (choice != null) { await Api.setMessageRetention(id, choice); await load(); }
      }
      if (action == 'reply') { setState(() { replyingTo = Map.from(m); }); input.selection = TextSelection.collapsed(offset: input.text.length); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Api.friendlyError(e)))); }
  }

  Widget _bubble(Map m) {
    final mine = _mine(m);
    final kind = (m['kind'] ?? 'text').toString();
    final isStatus = kind == 'status_like' || kind == 'status_reply';
    final body = _cleanBody((m['body'] ?? '').toString());

    final callLink = RegExp(r'https://meet\.jit\.si/[^\s]+').firstMatch(body)?.group(0);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(onHorizontalDragEnd: (details) { final velocity = details.primaryVelocity ?? 0; if (velocity.abs() > 250) setState(() { replyingTo = Map.from(m); input.selection = TextSelection.collapsed(offset: input.text.length); }); }, onLongPress: () => _messageActions(m), onTap: callLink == null ? null : () async { final uri = Uri.tryParse(callLink); if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication); }, child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.fromLTRB(
            isStatus ? 6 : 14, isStatus ? 6 : 10, isStatus ? 6 : 14, 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .76),
        decoration: BoxDecoration(
          gradient: mine ? OsColors.brandGradient : null,
          color: mine ? null : OsColors.surface2,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m['parent_message_id'] != null) ...[
              Builder(builder: (context) {
                final parentId = int.tryParse('${m['parent_message_id']}');
                Map? parent;
                for (final raw in ms) {
                  if (raw is Map && int.tryParse('${raw['id']}') == parentId) { parent = raw; break; }
                }
                return Container(width: double.infinity, padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 7), decoration: BoxDecoration(color: Colors.black.withOpacity(0.18), borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: OsColors.amber, width: 3))), child: Text(parent == null ? 'Reply to a message' : _cleanBody('${parent['body'] ?? ''}'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)));
              }),
            ],
            if (isStatus) ...[
              _StatusQuote(message: m, mine: mine, kind: kind),
              const SizedBox(height: 8),
            ],
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isStatus ? 8 : 0),
              child: Text(
                body,
                style: TextStyle(
                  height: 1.35,
                  color: Colors.white,
                  fontSize: kind == 'status_like' ? 14 : null,
                  fontWeight:
                      kind == 'status_like' ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (m['expires_at'] != null || m['my_expires_at'] != null)
              Padding(padding: const EdgeInsets.only(top: 5), child: Text(
                'Sender’s timer: ${m['expires_at'] == null ? 'indefinite' : _expiryLabel(m['expires_at'])}\nYour copy: ${m['my_expires_at'] == null ? 'indefinite' : _expiryLabel(m['my_expires_at'])}',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              )),
            if (m['my_reaction'] != null || (m['reactions'] is List && (m['reactions'] as List).isNotEmpty))
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('❤️ ${m['my_reaction'] ?? ''}', style: const TextStyle(fontSize: 11, color: Colors.white70))),
          ],
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.person['display_name'] ?? '?').toString();
    final verified = isVerifiedUser(widget.person);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(onTap: _openPersonProfile, child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, gradient: OsColors.brandGradient),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, fontWeight: isAdminUser(widget.person) ? FontWeight.w900 : null, color: isAdminUser(widget.person) ? kAdminGold : null)),
          ),
          if (verified)
            Padding(
              padding: const EdgeInsets.only(left: 5),
              child: UserBadge(user: widget.person, size: 16),
            ),
        ])),
        actions: [
          IconButton(tooltip: 'Audio call', onPressed: () => _startCall(video: false), icon: const Icon(Icons.call_outlined)),
          IconButton(tooltip: 'Video call', onPressed: () => _startCall(video: true), icon: const Icon(Icons.videocam_outlined)),
          PopupMenuButton<String>(
            color: OsColors.surface2,
            onSelected: (v) { if (v == 'report') _report(); else if (v == 'block') _block(); else if (v == 'whatsapp') _launchContact('whatsapp'); else if (v == 'phone') _launchContact('phone'); else if (v == 'clear') _clearChat(); },
            itemBuilder: (_) => [
              if ('${widget.person['phone_number'] ?? ''}'.trim().isNotEmpty) ...[
                const PopupMenuItem(value: 'whatsapp', child: Text('Open WhatsApp')),
                const PopupMenuItem(value: 'phone', child: Text('Call phone number')),
              ],
              const PopupMenuItem(value: 'report', child: Text('Report')),
              const PopupMenuItem(value: 'block', child: Text('Block')),
              const PopupMenuItem(value: 'clear', child: Text('Clear chat for me')),
            ],
          ),
        ],
      ),
      body: ResponsiveBody(maxWidth: 860, child: Column(children: [
        Expanded(
          child: !loaded
              ? const Center(child: CircularProgressIndicator())
              : ms.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.waving_hand_rounded, size: 44, color: OsColors.amber),
                          const SizedBox(height: 14),
                          Text('Say hi to $name',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          const Text('Start with something genuine. First messages matter.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: OsColors.muted)),
                        ]),
                      ),
                    )
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      itemCount: ms.length,
                      itemBuilder: (_, i) {
                        final m = ms[i] is Map ? ms[i] as Map : <String, dynamic>{};
                        return _bubble(m);
                      },
                    ),
        ),
        if (otherTyping) const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Align(alignment: Alignment.centerLeft, child: _TypingBubble()),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: const BoxDecoration(
              color: OsColors.bg,
              border: Border(top: BorderSide(color: OsColors.border)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (replyingTo != null) Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: OsColors.surface2, borderRadius: BorderRadius.circular(10)), child: Row(children: [Expanded(child: Text('Replying to: ${(replyingTo!['body'] ?? '').toString()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OsColors.muted, fontSize: 12))), IconButton(visualDensity: VisualDensity.compact, onPressed: () => setState(() => replyingTo = null), icon: const Icon(Icons.close, size: 18))])),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              PopupMenuButton<int?>(
                tooltip: 'Message retention',
                initialValue: expirySeconds,
                onSelected: (value) async {
                  if (value == -1) {
                    final hoursController = TextEditingController(text: '48');
                    final hours = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
                      title: const Text('Custom message duration'),
                      content: TextField(controller: hoursController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hours (1–720)')),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { final n = int.tryParse(hoursController.text); if (n != null && n >= 1 && n <= 720) Navigator.pop(ctx, n); }, child: const Text('Apply'))],
                    ));
                    hoursController.dispose();
                    if (hours != null && mounted) setState(() => expirySeconds = hours * 3600);
                  } else { setState(() => expirySeconds = value); }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<int?>(value: 3600, child: Text('Delete after 1 hour')),
                  PopupMenuItem<int?>(value: 86400, child: Text('Delete after 24 hours')),
                  PopupMenuItem<int?>(value: 604800, child: Text('Delete after 7 days')),
                  PopupMenuItem<int?>(value: 2592000, child: Text('Delete after 30 days')),
                  PopupMenuItem<int?>(value: -1, child: Text('Choose custom duration…')),
                  PopupMenuItem<int?>(value: null, child: Text('Save indefinitely')),
                ],
                icon: const Icon(Icons.timer_outlined),
              ),
              IconButton(
                tooltip: 'Naija icebreakers',
                onPressed: sending ? null : () async {
                  try {
                    final prompts = await Api.icebreakers(category: 'naija');
                    if (!context.mounted) return;
                    final selected = await showModalBottomSheet<String>(
                      context: context,
                      showDragHandle: true,
                      backgroundColor: OsColors.surface,
                      builder: (sheetContext) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(16),
                          children: [
                            const Text('Start with a better question',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            for (final prompt in prompts)
                              ListTile(
                                leading: const Icon(Icons.chat_bubble_outline_rounded, color: OsColors.purple),
                                title: Text(prompt.toString()),
                                onTap: () => Navigator.pop(sheetContext, prompt.toString()),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (selected != null && mounted) {
                      input.text = selected;
                      input.selection = TextSelection.collapsed(offset: input.text.length);
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not load icebreakers. ${Api.friendlyError(e)}')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.lightbulb_outline_rounded),
              ),
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Write a message…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: OsColors.border)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: OsColors.border)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: OsColors.purple, width: 1.4)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                    backgroundColor: OsColors.purpleDeep,
                    minimumSize: const Size(50, 50)),
                onPressed: sending || !hasText ? null : send,
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
              ),
              ]),
            ]),
          ),
        ),
      ])),
    );
  }
}

class _ChatPublicProfileRoute extends StatelessWidget {
  final Map<String, dynamic> user;
  const _ChatPublicProfileRoute({required this.user});
  @override
  Widget build(BuildContext context) {
    final name = (user['display_name'] ?? 'OS member').toString();
    return Scaffold(appBar: AppBar(title: const Text('Profile')), body: ListView(padding: const EdgeInsets.all(24), children: [
      CircleAvatar(radius: 48, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 30))),
      const SizedBox(height: 16), Center(child: Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
      if (isVerifiedUser(user)) Center(child: UserBadge(user: user, size: 24)),
      const SizedBox(height: 16), Text((user['bio'] ?? 'No bio yet.').toString()),
      const SizedBox(height: 8), Text((user['city'] ?? '').toString()),
      if ((user['phone_number'] ?? '').toString().isNotEmpty) Text('Phone: ${user['phone_number']}'),
    ]));
  }
}

// ============================================================
// QUOTED STATUS (shown above a status like / status reply)
// ============================================================

class _StatusQuote extends StatelessWidget {
  final Map message;
  final bool mine;
  final String kind;

  const _StatusQuote({
    required this.message,
    required this.mine,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final preview = (message['status_preview'] ?? '').toString().trim();
    final mediaKey = (message['status_media_key'] ?? '').toString().trim();
    final hasMedia = mediaKey.isNotEmpty;

    final label = kind == 'status_like'
        ? (mine ? 'You liked a status' : 'Liked your status')
        : (mine ? 'You replied to a status' : 'Replied to your status');

    final fallback = hasMedia ? 'Photo or video status' : 'Status';

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: OsColors.amber),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 12, color: OsColors.amber),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: OsColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview.isEmpty ? fallback : preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasMedia) _StatusThumb(mediaKey: mediaKey),
          ],
        ),
      ),
    );
  }
}

class _StatusThumb extends StatefulWidget {
  final String mediaKey;

  const _StatusThumb({required this.mediaKey});

  @override
  State<_StatusThumb> createState() => _StatusThumbState();
}

class _StatusThumbState extends State<_StatusThumb> {
  String? url;
  bool failed = false;

  bool get isVideo {
    final key = widget.mediaKey.toLowerCase().split('?').first;
    return key.endsWith('.mp4') ||
        key.endsWith('.mov') ||
        key.endsWith('.m4v') ||
        key.endsWith('.webm');
  }

  @override
  void initState() {
    super.initState();
    if (!isVideo) _load();
  }

  Future<void> _load() async {
    try {
      final result = await Api.mediaUrl(widget.mediaKey);
      if (!mounted) return;
      setState(() => url = result);
    } catch (_) {
      if (!mounted) return;
      setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (isVideo) {
      child = const Center(
        child: Icon(Icons.play_circle_fill_rounded,
            color: Colors.white, size: 28),
      );
    } else if (failed) {
      child = const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white54, size: 22),
      );
    } else if (url == null) {
      child = const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      child = Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 22),
        ),
      );
    }

    return SizedBox(
      width: 62,
      child: ColoredBox(color: Colors.black54, child: child),
    );
  }
}

class _TypingBubble extends StatefulWidget { const _TypingBubble(); @override State<_TypingBubble> createState() => _TypingBubbleState(); }
class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _controller, builder: (_, __) { final count = 1 + ((_controller.value * 3).floor() % 3); return Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(color: OsColors.surface2, borderRadius: BorderRadius.circular(18)), child: Text('typing${List<String>.filled(count, '.').join()}', style: const TextStyle(color: OsColors.muted, fontWeight: FontWeight.w700))); });
}
