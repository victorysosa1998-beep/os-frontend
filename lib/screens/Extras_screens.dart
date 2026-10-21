import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:record/record.dart' as rec;
import 'package:video_player/video_player.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';
import 'app_shell.dart';
import 'chat_screen.dart';

// =====================================================================
// Shared helpers
// =====================================================================
String _mmss(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${(s ~/ 60).toString().padLeft(1, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _clean(Object e) => '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

// =====================================================================
// 1) VOICE: recorder panel, clip player, voice intro card, voice status
// =====================================================================
class RecordedClip {
  final File file;
  final int seconds;
  const RecordedClip(this.file, this.seconds);
}

/// Record -> preview -> confirm. Used for the voice intro and voice statuses.
class VoiceRecorderPanel extends StatefulWidget {
  final int maxSeconds;
  final String doneLabel;
  final ValueChanged<RecordedClip> onDone;

  const VoiceRecorderPanel({
    super.key,
    required this.onDone,
    this.maxSeconds = 30,
    this.doneLabel = 'Use this recording',
  });

  @override
  State<VoiceRecorderPanel> createState() => _VoiceRecorderPanelState();
}

class _VoiceRecorderPanelState extends State<VoiceRecorderPanel> {
  final rec.AudioRecorder _rec = rec.AudioRecorder();
  Timer? _timer;
  bool recording = false;
  int elapsed = 0;
  RecordedClip? clip;
  VideoPlayerController? _player;
  String? error;

  @override
  void dispose() {
    _timer?.cancel();
    if (recording) {
      unawaited(_rec.cancel());
    }
    unawaited(_rec.dispose());
    _player?.dispose();
    super.dispose();
  }

  Future<void> _discardPreview() async {
    final p = _player;
    _player = null;
    await p?.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => error = 'Microphone permission is needed to record.');
        return;
      }
      await _discardPreview();
      final path =
          '${Directory.systemTemp.path}/os_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const rec.RecordConfig(
          encoder: rec.AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        recording = true;
        elapsed = 0;
        clip = null;
        error = null;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => elapsed++);
        if (elapsed >= widget.maxSeconds) _stop();
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not start recording: ${_clean(e)}');
    }
  }

  Future<void> _stop() async {
    if (!recording) return;
    _timer?.cancel();
    recording = false;
    try {
      final path = await _rec.stop();
      if (!mounted) return;
      if (path == null || elapsed < 2) {
        setState(() => error = 'That was too short. Record at least 2 seconds.');
        return;
      }
      final file = File(path);
      final player = VideoPlayerController.file(file);
      await player.initialize();
      player.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        clip = RecordedClip(file, elapsed);
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = 'Could not save the recording: ${_clean(e)}');
    }
  }

  Future<void> _togglePreview() async {
    final p = _player;
    if (p == null) return;
    if (p.value.isPlaying) {
      await p.pause();
    } else {
      if (p.value.position >= p.value.duration) await p.seekTo(Duration.zero);
      await p.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasClip = clip != null && !recording;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: hasClip ? null : (recording ? _stop : _start),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: recording ? 112 : 96,
            height: recording ? 112 : 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: recording ? null : OsColors.brandGradient,
              color: recording ? OsColors.coral : null,
              boxShadow: [
                BoxShadow(
                  color: (recording ? OsColors.coral : OsColors.purpleDeep).withValues(alpha: .45),
                  blurRadius: recording ? 40 : 24,
                  spreadRadius: recording ? 6 : 1,
                ),
              ],
            ),
            child: Icon(
              hasClip ? Icons.check_rounded : (recording ? Icons.stop_rounded : Icons.mic_rounded),
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          recording
              ? '${_mmss(elapsed)} / ${_mmss(widget.maxSeconds)}   Tap to stop'
              : hasClip
                  ? 'Recorded ${_mmss(clip!.seconds)}'
                  : 'Tap the mic and start talking (up to ${widget.maxSeconds}s)',
          style: const TextStyle(color: OsColors.muted),
          textAlign: TextAlign.center,
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
        ],
        if (hasClip) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _togglePreview,
                icon: Icon(_player?.value.isPlaying == true ? Icons.pause : Icons.play_arrow),
                label: Text(_player?.value.isPlaying == true ? 'Pause' : 'Listen'),
              ),
              const SizedBox(width: 10),
              TextButton(onPressed: _start, child: const Text('Re-record')),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: () => widget.onDone(clip!),
            child: Text(widget.doneLabel),
          ),
        ],
      ],
    );
  }
}

/// Plays a remote audio clip. The URL is fetched lazily when play is tapped
/// (presigned URLs are short-lived).
class VoiceClipPlayer extends StatefulWidget {
  final Future<String> Function() loadUrl;
  final int? seconds;
  final bool compact;
  final String label;

  const VoiceClipPlayer({
    super.key,
    required this.loadUrl,
    this.seconds,
    this.compact = false,
    this.label = 'Voice',
  });

  @override
  State<VoiceClipPlayer> createState() => _VoiceClipPlayerState();
}

class _VoiceClipPlayerState extends State<VoiceClipPlayer> {
  VideoPlayerController? _c;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  bool get playing => _c?.value.isPlaying == true;

  Future<void> _toggle() async {
    if (loading) return;
    try {
      var c = _c;
      if (c == null) {
        setState(() {
          loading = true;
          error = null;
        });
        final url = await widget.loadUrl();
        c = VideoPlayerController.networkUrl(Uri.parse(url));
        await c.initialize();
        c.addListener(() {
          if (mounted) setState(() {});
        });
        if (!mounted) {
          await c.dispose();
          return;
        }
        _c = c;
        loading = false;
        await c.play();
      } else if (c.value.isPlaying) {
        await c.pause();
      } else {
        if (c.value.position >= c.value.duration) await c.seekTo(Duration.zero);
        await c.play();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not play this clip.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final total = (c != null && c.value.isInitialized && c.value.duration.inSeconds > 0)
        ? c.value.duration.inSeconds
        : (widget.seconds ?? 0);
    final pos = c?.value.position.inSeconds ?? 0;
    final progress = (c != null && c.value.isInitialized && c.value.duration.inMilliseconds > 0)
        ? (c.value.position.inMilliseconds / c.value.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final button = SizedBox(
      width: widget.compact ? 52 : 46,
      height: widget.compact ? 52 : 46,
      child: FilledButton(
        onPressed: _toggle,
        style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
        child: loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
      ),
    );

    if (widget.compact) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF332456), Color(0xFF1B1730)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.graphic_eq_rounded, color: Colors.white70),
            const SizedBox(height: 6),
            button,
            if (total > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_mmss(total), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ),
          ]),
        ),
      );
    }

    return Container(
      height: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF332456), Color(0xFF1B1730), Color(0xFF352039)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.graphic_eq_rounded, size: 54, color: Colors.white70),
          const SizedBox(height: 10),
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            button,
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: progress, minHeight: 4),
                const SizedBox(height: 6),
                Text('${_mmss(pos)} / ${_mmss(total)}',
                    style: const TextStyle(color: OsColors.muted, fontSize: 12)),
              ]),
            ),
          ]),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// Voice intro on a profile. [editable] shows record / replace / delete.
class VoiceBioCard extends StatefulWidget {
  final int userId;
  final bool editable;
  const VoiceBioCard({super.key, required this.userId, this.editable = false});

  @override
  State<VoiceBioCard> createState() => _VoiceBioCardState();
}

class _VoiceBioCardState extends State<VoiceBioCard> {
  Map<String, dynamic>? data;
  bool loading = true;
  bool busy = false;
  int version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.voiceBio(widget.userId);
      if (!mounted) return;
      setState(() {
        data = r;
        loading = false;
        version++;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get has => data?['has'] == true;

  Future<void> _record() async {
    final clip = await showModalBottomSheet<RecordedClip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OsColors.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Record your voice intro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Say hi in your own words. People who hear you tend to trust you faster.',
              textAlign: TextAlign.center, style: TextStyle(color: OsColors.muted)),
          const SizedBox(height: 20),
          VoiceRecorderPanel(
            maxSeconds: 30,
            doneLabel: 'Save voice intro',
            onDone: (c) => Navigator.pop(ctx, c),
          ),
        ]),
      ),
    );
    if (clip == null || !mounted) return;
    setState(() => busy = true);
    try {
      final up = await Api.upload(clip.file, 'voice_bio', 'audio/mp4');
      final key = '${up['object_key'] ?? up['key'] ?? ''}';
      if (key.isEmpty) throw Exception('Upload did not return a key.');
      await Api.setVoiceBio(key, clip.seconds);
      await _load();
      _snack(context, 'Voice intro saved.');
    } catch (e) {
      _snack(context, 'Could not save voice intro: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => busy = true);
    try {
      await Api.deleteVoiceBio();
      await _load();
    } catch (e) {
      _snack(context, 'Could not delete: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox.shrink();
    if (!has && !widget.editable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.record_voice_over_rounded, color: OsColors.purple, size: 20),
            SizedBox(width: 8),
            Text('Voice intro', style: TextStyle(fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 10),
          if (has)
            VoiceClipPlayer(
              key: ValueKey(version),
              loadUrl: () async {
                final r = await Api.voiceBio(widget.userId);
                return '${r['url']}';
              },
              seconds: int.tryParse('${data?['duration_seconds'] ?? ''}'),
              label: 'Hear their voice',
            )
          else
            const Text('Add a 30-second voice intro. It makes your profile feel real.',
                style: TextStyle(color: OsColors.muted)),
          if (widget.editable) ...[
            const SizedBox(height: 10),
            Row(children: [
              FilledButton.icon(
                onPressed: busy ? null : _record,
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.mic_rounded),
                label: Text(has ? 'Replace' : 'Record intro'),
              ),
              if (has) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: busy ? null : _delete, child: const Text('Delete')),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Post a voice status (a normal post whose media is an audio clip).
class VoiceStatusScreen extends StatefulWidget {
  const VoiceStatusScreen({super.key});

  @override
  State<VoiceStatusScreen> createState() => _VoiceStatusScreenState();
}

class _VoiceStatusScreenState extends State<VoiceStatusScreen> {
  RecordedClip? clip;
  final caption = TextEditingController();
  bool posting = false;
  String? error;

  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final c = clip;
    if (c == null || posting) return;
    setState(() {
      posting = true;
      error = null;
    });
    try {
      final up = await Api.upload(c.file, 'post', 'audio/mp4');
      final key = '${up['object_key'] ?? up['key'] ?? ''}';
      if (key.isEmpty) throw Exception('Upload did not return a key.');
      await Api.createPost(caption.text.trim(), key);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          posting = false;
          error = _clean(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice status')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (clip == null) ...[
            const SizedBox(height: 20),
            const Text('Say it, don\'t type it',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Share a voice note as your status (up to 60 seconds).',
                textAlign: TextAlign.center, style: TextStyle(color: OsColors.muted)),
            const SizedBox(height: 30),
            VoiceRecorderPanel(
              maxSeconds: 60,
              doneLabel: 'Continue',
              onDone: (c) => setState(() => clip = c),
            ),
          ] else ...[
            const Icon(Icons.graphic_eq_rounded, size: 60, color: OsColors.purple),
            const SizedBox(height: 10),
            Text('Voice note ready (${_mmss(clip!.seconds)})',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 20),
            TextField(
              controller: caption,
              enabled: !posting,
              maxLength: 300,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Add a caption (optional)', counterText: ''),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              TextButton(onPressed: posting ? null : () => setState(() => clip = null), child: const Text('Re-record')),
              const Spacer(),
              FilledButton.icon(
                onPressed: posting ? null : _post,
                icon: posting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: Text(posting ? 'Posting...' : 'Post status'),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

// =====================================================================
// 2) DATE SAFETY KIT
// =====================================================================
class SafetyKitScreen extends StatefulWidget {
  const SafetyKitScreen({super.key});

  @override
  State<SafetyKitScreen> createState() => _SafetyKitScreenState();
}

class _SafetyKitScreenState extends State<SafetyKitScreen> {
  List<Map<String, dynamic>> contacts = [];
  Map<String, dynamic>? active;
  bool loading = true;
  bool busy = false;
  String? error;

  final partner = TextEditingController();
  final place = TextEditingController();
  int minutes = 120;
  final Set<int> selected = {};

  Timer? _tick;
  Timer? _loc;
  DateTime? _due;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && active != null) setState(() {});
    });
    _loc = Timer.periodic(const Duration(seconds: 60), (_) => _pushLocation());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _loc?.cancel();
    partner.dispose();
    place.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await Api.safetyContacts();
      final a = await Api.activeCheckin();
      if (!mounted) return;
      final list = (c['items'] as List? ?? []).map(_map).toList();
      setState(() {
        contacts = list;
        active = a['checkin'] == null ? null : _map(a['checkin']);
        _due = active == null ? null : DateTime.tryParse('${active!['due_at']}');
        if (selected.isEmpty) selected.addAll(list.map((e) => e['id'] as int));
        loading = false;
        error = null;
      });
      _pushLocation();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = _clean(e);
        });
      }
    }
  }

  Future<void> _pushLocation() async {
    final a = active;
    if (a == null || (a['status'] != 'active' && a['status'] != 'alerted')) return;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final pos = await Geolocator.getCurrentPosition();
      await Api.checkinLocation(a['id'] as int, pos.latitude, pos.longitude);
    } catch (_) {}
  }

  Future<void> _addContact() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _AddContactDialog(),
    );
    if (result == null) return;
    setState(() => busy = true);
    try {
      final created = await Api.addSafetyContact(result['name']!, result['email']!);
      selected.add(created['id'] as int);
      await _load();
      _snack(context, 'Trusted contact added. We emailed them to let them know.');
    } catch (e) {
      _snack(context, _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _removeContact(Map<String, dynamic> c) async {
    try {
      await Api.deleteSafetyContact(c['id'] as int);
      selected.remove(c['id']);
      await _load();
    } catch (e) {
      _snack(context, _clean(e));
    }
  }

  Future<void> _start() async {
    if (partner.text.trim().isEmpty) {
      setState(() => error = 'Enter who you are meeting.');
      return;
    }
    if (selected.isEmpty) {
      setState(() => error = 'Choose at least one trusted contact.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await Api.startCheckin(
        partnerName: partner.text.trim(),
        place: place.text.trim(),
        minutes: minutes,
        contactIds: selected.toList(),
      );
      partner.clear();
      place.clear();
      setState(() {
        active = r;
        _due = DateTime.tryParse('${r['due_at']}');
      });
      _pushLocation();
    } catch (e) {
      setState(() => error = _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _safe() async {
    final a = active;
    if (a == null) return;
    setState(() => busy = true);
    try {
      await Api.safeCheckin(a['id'] as int);
      if (!mounted) return;
      setState(() {
        active = null;
        _due = null;
      });
      _snack(context, 'Glad you\'re safe. Your contacts have been told.');
    } catch (e) {
      _snack(context, _clean(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _extend() async {
    final a = active;
    if (a == null) return;
    try {
      final r = await Api.extendCheckin(a['id'] as int, 30);
      setState(() {
        active = r;
        _due = DateTime.tryParse('${r['due_at']}');
      });
    } catch (e) {
      _snack(context, _clean(e));
    }
  }

  Future<void> _sos() async {
    final a = active;
    if (a == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OsColors.surface,
        title: const Text('Send SOS?'),
        content: const Text('Your trusted contacts will be emailed right now with your last known location.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _pushLocation();
    try {
      final r = await Api.sosCheckin(a['id'] as int);
      setState(() => active = r);
      _snack(context, 'SOS sent to your trusted contacts. If you are in danger, call 112.');
    } catch (e) {
      _snack(context, _clean(e));
    }
  }

  int get _secondsLeft {
    final due = _due;
    if (due == null) return 0;
    return due.difference(DateTime.now()).inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Date safety kit')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const OsCard(
                    child: Row(children: [
                      Icon(Icons.health_and_safety_rounded, color: OsColors.purple, size: 30),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Going on a date? Tell us who, where and for how long. If you don\'t check in as safe, '
                          'your trusted contacts are alerted automatically.',
                          style: TextStyle(height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  if (active != null) _activeCard() else _startCard(),
                  const SizedBox(height: 14),
                  _contactsCard(),
                  if (error != null && active == null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Location is shared with your contacts while this screen is open. In an emergency call 112 or 199.',
                    style: TextStyle(color: OsColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _activeCard() {
    final a = active!;
    final alerted = a['status'] == 'alerted';
    final left = _secondsLeft;
    final overdue = left < 0;
    final color = alerted ? Colors.redAccent : (overdue ? OsColors.amber : Colors.green);
    return OsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(alerted ? Icons.warning_amber_rounded : Icons.shield_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alerted ? 'Your contacts were alerted' : 'Date check-in is active',
              style: TextStyle(fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text('Meeting ${a['partner_name']}${('${a['place']}').isEmpty ? '' : ' at ${a['place']}'}'),
        const SizedBox(height: 14),
        Center(
          child: Text(
            alerted
                ? 'Tap I\'m safe if you are okay'
                : overdue
                    ? 'Time is up: check in now'
                    : _mmss(left),
            style: TextStyle(fontSize: overdue || alerted ? 18 : 44, fontWeight: FontWeight.w900, color: color),
          ),
        ),
        if (!alerted && !overdue)
          const Center(child: Text('until you check in', style: TextStyle(color: OsColors.muted, fontSize: 12))),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: busy ? null : _safe,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('I\'m safe'),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (!alerted)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _extend,
                icon: const Icon(Icons.more_time_rounded),
                label: const Text('+30 min'),
              ),
            ),
          if (!alerted) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
              onPressed: alerted ? null : _sos,
              icon: const Icon(Icons.sos_rounded, color: Colors.redAccent),
              label: const Text('SOS', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ]),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: '${a['share_url']}'));
            _snack(context, 'Live link copied.');
          },
          icon: const Icon(Icons.link_rounded),
          label: const Text('Copy live link for a contact'),
        ),
      ]),
    );
  }

  Widget _startCard() {
    return OsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Start a date check-in', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 12),
        TextField(
          controller: partner,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Who are you meeting?', prefixIcon: Icon(Icons.person_outline)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: place,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Where? (restaurant, mall, area)', prefixIcon: Icon(Icons.place_outlined)),
        ),
        const SizedBox(height: 12),
        const Text('Check in within', style: TextStyle(color: OsColors.muted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final m in [60, 120, 180, 240])
            ChoiceChip(
              label: Text('${m ~/ 60}h'),
              selected: minutes == m,
              onSelected: busy ? null : (_) => setState(() => minutes = m),
            ),
        ]),
        const SizedBox(height: 12),
        const Text('Alert these contacts', style: TextStyle(color: OsColors.muted, fontSize: 12)),
        if (contacts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('Add a trusted contact below first.'),
          )
        else
          for (final c in contacts)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: selected.contains(c['id']),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          selected.add(c['id'] as int);
                        } else {
                          selected.remove(c['id']);
                        }
                      }),
              title: Text('${c['name']}'),
              subtitle: Text('${c['email']}'),
            ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy || contacts.isEmpty ? null : _start,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.shield_outlined),
            label: const Text('Start check-in'),
          ),
        ),
      ]),
    );
  }

  Widget _contactsCard() {
    return OsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Trusted contacts', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          TextButton.icon(
            onPressed: busy || contacts.length >= 5 ? null : _addContact,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add'),
          ),
        ]),
        if (contacts.isEmpty)
          const Text('Add a friend or family member who will be alerted if you don\'t check in.',
              style: TextStyle(color: OsColors.muted)),
        for (final c in contacts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 18)),
            title: Text('${c['name']}'),
            subtitle: Text('${c['email']}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _removeContact(c),
            ),
          ),
      ]),
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final name = TextEditingController();
  final email = TextEditingController();
  String? error;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: OsColors.surface,
        title: const Text('Add trusted contact'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email address'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              final e = email.text.trim();
              if (n.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
                setState(() => error = 'Enter a name and a valid email.');
                return;
              }
              Navigator.pop(context, {'name': n, 'email': e});
            },
            child: const Text('Add'),
          ),
        ],
      );
}

// =====================================================================
// 3) BLIND VOICE DATE
// =====================================================================
enum _BlindStage { intro, searching, call, deciding, waiting, result }

const List<String> _blindPrompts = [
  'Jollof showdown: party jollof or smoky jollof? Defend your answer.',
  'Which Afrobeats song can you never skip?',
  'Describe your perfect Sunday in 10 seconds.',
  'What is your Pidgin phrase for "this thing is nice"?',
  'Best street food you have ever had?',
  'Light just went off and the generator will not start. What is your move?',
  'What small thing reliably makes your day better?',
  'Give your most unpopular opinion. Go.',
];

class BlindDateScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  const BlindDateScreen({super.key, required this.user});

  @override
  State<BlindDateScreen> createState() => _BlindDateScreenState();
}

class _BlindDateScreenState extends State<BlindDateScreen> {
  _BlindStage stage = _BlindStage.intro;
  Map<String, dynamic> session = {};
  String? error;

  Timer? _poll;
  Timer? _clock;
  DateTime? _endsAt;
  int secondsLeft = 0;
  int promptIndex = 0;

  final Room room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
  bool _roomListening = false;
  bool muted = false;
  bool connecting = false;
  bool partnerHere = false;
  bool partnerSpeaking = false;
  bool leaving = false;

  int get sessionId => int.tryParse('${session['id']}') ?? 0;

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    if (_roomListening) room.removeListener(_onRoom);
    if (stage == _BlindStage.searching) {
      unawaited(Api.blindLeaveQueue().catchError((_) {}));
    }
    unawaited(() async {
      try {
        await room.disconnect();
      } catch (_) {}
      try {
        await room.dispose();
      } catch (_) {}
    }());
    super.dispose();
  }

  void _onRoom() {
    if (!mounted) return;
    final remotes = room.remoteParticipants.values.toList();
    setState(() {
      partnerHere = remotes.isNotEmpty;
      partnerSpeaking = remotes.any((p) => p.isSpeaking);
    });
  }

  // ---- matching ----
  Future<void> _join() async {
    setState(() => error = null);
    try {
      final r = await Api.blindJoin();
      if (!mounted) return;
      if (r['state'] == 'matched') {
        await _enterSession(_map(r['session']));
      } else {
        setState(() => stage = _BlindStage.searching);
        _poll?.cancel();
        _poll = Timer.periodic(const Duration(seconds: 2), (_) => _pollQueue());
      }
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    }
  }

  Future<void> _pollQueue() async {
    try {
      final r = await Api.blindState();
      if (!mounted) return;
      if (r['state'] == 'matched') {
        _poll?.cancel();
        await _enterSession(_map(r['session']));
      } else if (r['state'] == 'idle') {
        _poll?.cancel();
        setState(() {
          stage = _BlindStage.intro;
          error = 'No one was available right now. Try again in a little while.';
        });
      }
    } catch (_) {}
  }

  Future<void> _cancelSearch() async {
    _poll?.cancel();
    try {
      await Api.blindLeaveQueue();
    } catch (_) {}
    if (mounted) setState(() => stage = _BlindStage.intro);
  }

  // ---- the call ----
  Future<void> _enterSession(Map<String, dynamic> s) async {
    session = s;
    // If I already chose in an earlier visit, go straight to waiting.
    if (s['my_choice'] != null) {
      setState(() => stage = _BlindStage.waiting);
      _startResultPoll();
      return;
    }
    final left = int.tryParse('${s['seconds_left']}') ?? 0;
    if (left <= 0) {
      setState(() => stage = _BlindStage.deciding);
      return;
    }
    _endsAt = DateTime.now().add(Duration(seconds: left));
    setState(() {
      stage = _BlindStage.call;
      secondsLeft = left;
      promptIndex = DateTime.now().millisecond % _blindPrompts.length;
      muted = false;
      partnerHere = false;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _endsAt;
      if (!mounted || end == null) return;
      final left = end.difference(DateTime.now()).inSeconds;
      setState(() {
        secondsLeft = left < 0 ? 0 : left;
        if (secondsLeft > 0 && secondsLeft % 45 == 0) {
          promptIndex = (promptIndex + 1) % _blindPrompts.length;
        }
      });
      if (left <= 0) _finishTalk();
    });
    await _connect();
  }

  Future<void> _connect() async {
    if (connecting) return;
    setState(() {
      connecting = true;
      error = null;
    });
    try {
      final creds = await Api.blindToken(sessionId);
      final url = '${creds['server_url'] ?? ''}'.trim();
      final token = '${creds['participant_token'] ?? ''}'.trim();
      if (url.isEmpty || token.isEmpty) throw Exception('The call server did not return valid credentials.');
      if (!_roomListening) {
        room.addListener(_onRoom);
        _roomListening = true;
      }
      await room.connect(url, token);
      final local = room.localParticipant;
      await local?.setMicrophoneEnabled(true);
      try {
        await Hardware.instance.setSpeakerphoneOn(true);
      } catch (_) {}
      _onRoom();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not connect: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => connecting = false);
    }
  }

  Future<void> _toggleMute() async {
    try {
      await room.localParticipant?.setMicrophoneEnabled(muted);
      if (mounted) setState(() => muted = !muted);
    } catch (_) {}
  }

  Future<void> _finishTalk() async {
    if (stage != _BlindStage.call) return;
    _clock?.cancel();
    try {
      await room.disconnect();
    } catch (_) {}
    if (mounted) setState(() => stage = _BlindStage.deciding);
  }

  // ---- decision ----
  Future<void> _choose(String choice) async {
    try {
      final r = await Api.blindChoice(sessionId, choice);
      if (!mounted) return;
      session = r;
      if (r['result'] != null) {
        setState(() => stage = _BlindStage.result);
      } else {
        setState(() => stage = _BlindStage.waiting);
        _startResultPoll();
      }
    } catch (e) {
      if (mounted) setState(() => error = _clean(e));
    }
  }

  void _startResultPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final r = await Api.blindSession(sessionId);
        if (!mounted) return;
        if (r['result'] != null) {
          _poll?.cancel();
          setState(() {
            session = r;
            stage = _BlindStage.result;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _report() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OsColors.surface,
        title: const Text('Report this voice'),
        content: TextField(
          controller: controller,
          maxLength: 300,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'What happened?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, controller.text.trim()), child: const Text('Report')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 3) return;
    try {
      await Api.blindReport(sessionId, reason);
      _snack(context, 'Thanks. Our moderators will review this.');
      await _finishTalk();
    } catch (e) {
      _snack(context, _clean(e));
    }
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: OsColors.surface,
        title: const Text('Leave this voice date?'),
        content: const Text('Leaving counts as a pass.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    leaving = true;
    try {
      await Api.blindChoice(sessionId, 'pass');
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openChat() async {
    final partner = _map(session['partner']);
    final convId = int.tryParse('${session['conversation_id']}');
    if (convId == null) {
      _snack(context, 'Open the chat from your Chats tab.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: convId,
          person: partner,
          myId: widget.user['id'],
          profileBuilder: (id, profile) => PublicProfileScreen(userId: id, initialUser: profile),
        ),
      ),
    );
  }

  void _restart() {
    setState(() {
      session = {};
      error = null;
      stage = _BlindStage.intro;
    });
  }

  // ---- UI ----
  bool get _needsConfirm =>
      !leaving &&
      (stage == _BlindStage.call || stage == _BlindStage.deciding || stage == _BlindStage.waiting);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_needsConfirm,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Blind voice date')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: switch (stage) {
              _BlindStage.intro => _intro(),
              _BlindStage.searching => _searching(),
              _BlindStage.call => _call(),
              _BlindStage.deciding => _deciding(),
              _BlindStage.waiting => _waiting(),
              _BlindStage.result => _result(),
            },
          ),
        ),
      ),
    );
  }

  Widget _orb({required bool active, IconData icon = Icons.graphic_eq_rounded}) => AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: active ? 170 : 140,
        height: active ? 170 : 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: OsColors.brandGradient,
          boxShadow: [
            BoxShadow(
              color: OsColors.purpleDeep.withValues(alpha: active ? .7 : .4),
              blurRadius: active ? 70 : 40,
              spreadRadius: active ? 10 : 2,
            ),
          ],
        ),
        child: Icon(icon, size: 60, color: Colors.white),
      );

  Widget _intro() => ListView(children: [
        const SizedBox(height: 10),
        Center(child: _orb(active: false, icon: Icons.record_voice_over_rounded)),
        const SizedBox(height: 28),
        const Text('Fall for the voice first',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        const Text(
          'Get matched with another verified member for a 5-minute, voice-only chat. '
          'No photos, no names. When time is up, you both choose: reveal or pass. '
          'Only if you both reveal do you see each other and unlock chat.',
          textAlign: TextAlign.center,
          style: TextStyle(color: OsColors.muted, height: 1.5),
        ),
        const SizedBox(height: 22),
        const OsCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How it works', style: TextStyle(fontWeight: FontWeight.w900)),
            SizedBox(height: 8),
            Text('1. We match you with a verified member.\n2. Talk for 5 minutes. Prompts help if you go quiet.\n'
                '3. Both tap Reveal to match, or Pass to move on.\n4. Report anyone who makes you uncomfortable.',
                style: TextStyle(height: 1.5)),
          ]),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _join,
          icon: const Icon(Icons.mic_rounded),
          label: const Text('Find my voice date'),
        ),
      ]);

  Widget _searching() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _orb(active: true, icon: Icons.search_rounded),
        const SizedBox(height: 30),
        const Text('Finding someone to talk to...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Keep this screen open. This can take a minute.', style: TextStyle(color: OsColors.muted)),
        const SizedBox(height: 28),
        OutlinedButton(onPressed: _cancelSearch, child: const Text('Cancel')),
      ]);

  Widget _call() => Column(children: [
        const SizedBox(height: 4),
        Text(_mmss(secondsLeft),
            style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 4),
        Text(
          connecting
              ? 'Connecting...'
              : partnerHere
                  ? 'Mystery voice is on the line'
                  : 'Waiting for your match to join...',
          style: const TextStyle(color: OsColors.muted),
        ),
        const Spacer(),
        _orb(active: partnerSpeaking),
        const Spacer(),
        OsCard(
          child: Row(children: [
            const Icon(Icons.lightbulb_outline_rounded, color: OsColors.amber),
            const SizedBox(width: 10),
            Expanded(child: Text(_blindPrompts[promptIndex], style: const TextStyle(height: 1.4))),
            IconButton(
              tooltip: 'Another prompt',
              onPressed: () => setState(() => promptIndex = (promptIndex + 1) % _blindPrompts.length),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ]),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          TextButton(onPressed: connecting ? null : _connect, child: const Text('Retry connection')),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _roundButton(muted ? Icons.mic_off : Icons.mic, muted ? 'Unmute' : 'Mute', _toggleMute),
          _roundButton(Icons.flag_outlined, 'Report', _report),
          _roundButton(Icons.call_end, 'End & decide', _finishTalk, color: const Color(0xFFE54555)),
        ]),
        const SizedBox(height: 8),
      ]);

  Widget _roundButton(IconData icon, String label, VoidCallback onTap, {Color? color}) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 58,
          height: 58,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: color ?? OsColors.surface2,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: Icon(icon),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: OsColors.muted, fontSize: 12)),
      ]);

  Widget _deciding() => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.hourglass_bottom_rounded, size: 64, color: OsColors.purple),
        const SizedBox(height: 18),
        const Text('Time is up!', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('Did you like their vibe? You only match if you both say reveal.',
            textAlign: TextAlign.center, style: TextStyle(color: OsColors.muted)),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => _choose('reveal'),
            icon: const Icon(Icons.visibility_rounded),
            label: const Text('Reveal me'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => _choose('pass'),
            child: const Text('Pass'),
          ),
        ),
      ]);

  Widget _waiting() => const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(),
        SizedBox(height: 22),
        Text('Waiting for them to decide...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Text('This takes a few seconds.', style: TextStyle(color: OsColors.muted)),
      ]);

  Widget _result() {
    final match = session['result'] == 'match';
    final partner = _map(session['partner']);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (match) ...[
        AvatarPhoto(user: partner, radius: 56),
        const SizedBox(height: 18),
        const Text("It's a match!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text('You and ${partner['display_name'] ?? 'your match'} both chose to reveal.',
            textAlign: TextAlign.center, style: const TextStyle(color: OsColors.muted)),
        const SizedBox(height: 26),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _openChat,
            icon: const Icon(Icons.chat_bubble_rounded),
            label: const Text('Say hi'),
          ),
        ),
      ] else ...[
        const Icon(Icons.waving_hand_rounded, size: 64, color: OsColors.purple),
        const SizedBox(height: 18),
        const Text('Not a match this time', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text('That is okay. The next voice might be the one.',
            textAlign: TextAlign.center, style: TextStyle(color: OsColors.muted)),
      ],
      const SizedBox(height: 12),
      TextButton(onPressed: _restart, child: const Text('Try another voice date')),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
    ]);
  }
}

// =====================================================================
// Entry points: cards shown in the Chats tab
// =====================================================================
class FeaturesStrip extends StatelessWidget {
  final Map<String, dynamic> user;
  const FeaturesStrip({super.key, required this.user});

  Widget _card(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Color(0xFF332456), Color(0xFF1B1730)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: OsColors.muted, fontSize: 12, height: 1.3)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(children: [
        _card(
          context,
          icon: Icons.record_voice_over_rounded,
          title: 'Blind voice date',
          subtitle: '5 minutes, voices only',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => BlindDateScreen(user: user)),
          ),
        ),
        const SizedBox(width: 12),
        _card(
          context,
          icon: Icons.health_and_safety_rounded,
          title: 'Date safety',
          subtitle: 'Alert friends if you go quiet',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const SafetyKitScreen()),
          ),
        ),
      ]),
    );
  }
}