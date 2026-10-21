import 'dart:async';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import 'app_shell.dart' show AvatarPhoto;

/// One-to-one LiveKit call UI. The backend controls call permissions and
/// issues short-lived participant tokens; no LiveKit secret is shipped here.
///
/// Hang-up guarantees:
///  * tapping End (or the system back button) closes the screen immediately
///  * the media room is disconnected right away
///  * the server is told the call ended, with retries (idempotent endpoint)
///  * if the other person leaves, this side closes immediately too
class LiveCallScreen extends StatefulWidget {
  final Map<String, dynamic> call;
  final bool isCaller;
  const LiveCallScreen({super.key, required this.call, required this.isCaller});

  @override
  State<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends State<LiveCallScreen> {
  late final int callId;
  late final bool videoCall;
  late final String otherName;
  late final Map<String, dynamic> otherUser;
  final Room room = Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));
  late final EventsListener<RoomEvent> listener;
  Timer? statusTimer;
  Timer? clockTimer;
  DateTime? connectedAt;
  Duration elapsed = Duration.zero;
  bool connecting = false;
  bool connected = false;
  bool muted = false;
  bool cameraEnabled = true;
  bool speaker = true;
  bool hangingUp = false; // set the instant End is pressed
  bool tornDown = false;
  bool checking = false;
  String? error;
  String statusText = 'Connecting securely...';

  @override
  void initState() {
    super.initState();
    callId = int.tryParse('${widget.call['id']}') ?? 0;
    videoCall = widget.call['call_type'] == 'video';
    final other = widget.call['other_user'];
    otherUser = other is Map ? Map<String, dynamic>.from(other) : <String, dynamic>{};
    otherName = '${otherUser['display_name'] ?? 'OS member'}';
    cameraEnabled = videoCall;
    listener = room.createListener()
      ..on<ParticipantConnectedEvent>((_) => _refreshRoom())
      ..on<ParticipantDisconnectedEvent>((_) {
        // The other person left: end right away instead of waiting for polling.
        if (connected && room.remoteParticipants.isEmpty) {
          _hangUp(reason: 'The call ended.');
        } else {
          _refreshRoom();
        }
      })
      ..on<TrackSubscribedEvent>((_) => _refreshRoom())
      ..on<TrackUnsubscribedEvent>((_) => _refreshRoom())
      ..on<TrackMutedEvent>((_) => _refreshRoom())
      ..on<TrackUnmutedEvent>((_) => _refreshRoom())
      ..on<LocalTrackPublishedEvent>((_) => _refreshRoom())
      ..on<LocalTrackUnpublishedEvent>((_) => _refreshRoom())
      ..on<RoomDisconnectedEvent>((_) {
        if (connected && !hangingUp) _hangUp(reason: 'Call disconnected.');
      });
    room.addListener(_refreshRoom);
    statusTimer = Timer.periodic(const Duration(seconds: 1), (_) => _checkCall());
    _checkCall();
  }

  // ---------------------------------------------------------------- hang up

  /// Single exit path. Safe to call many times; only the first call acts.
  void _hangUp({String? reason, bool notifyServer = true}) {
    if (hangingUp) return;
    hangingUp = true;
    statusTimer?.cancel();
    clockTimer?.cancel();
    // 1) leave the screen NOW (no awaiting anything before this).
    if (mounted) {
      if (reason != null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(reason)));
      }
      Navigator.of(context).pop();
    }
    // 2) kill audio/video immediately and 3) tell the server, in parallel.
    unawaited(_teardown());
    if (notifyServer) unawaited(_notifyServerCallEnded());
  }

  Future<void> _teardown() async {
    if (tornDown) return;
    tornDown = true;
    try {
      await room.localParticipant?.setMicrophoneEnabled(false);
    } catch (_) {}
    try {
      await room.localParticipant?.setCameraEnabled(false);
    } catch (_) {}
    try {
      await room.disconnect();
    } catch (_) {}
    try {
      await room.dispose();
    } catch (_) {}
  }

  Future<void> _notifyServerCallEnded() async {
    if (callId <= 0) return;
    const delays = [
      Duration.zero,
      Duration(milliseconds: 500),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ];
    for (final delay in delays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      try {
        await Api.endCall(callId).timeout(const Duration(seconds: 8));
        return;
      } on ApiException catch (e) {
        // 404 means the call is already gone: nothing left to end.
        if (e.status == 404) return;
      } catch (_) {
        // Retry transient network failures. The backend also expires calls
        // whose heartbeat stops, so a lost request cannot hold the line open.
      }
    }
  }

  // ----------------------------------------------------------- call status

  Future<void> _checkCall() async {
    if (!mounted || hangingUp || callId <= 0 || checking) return;
    checking = true;
    try {
      final call = await Api.callStatus(callId);
      if (!mounted || hangingUp) return;
      final status = '${call['status'] ?? ''}';
      if (status == 'in_progress' && !connected && !connecting && error == null) {
        await _connect();
      } else if (['declined', 'ended', 'missed'].contains(status)) {
        final msg = status == 'declined' && widget.isCaller
            ? 'The call was declined.'
            : status == 'missed'
                ? 'No answer.'
                : 'The call ended.';
        // Server already knows it ended; no need to call /end again.
        _hangUp(reason: msg, notifyServer: false);
      } else if (status == 'ringing' && !connected) {
        setState(() => statusText = widget.isCaller ? 'Ringing $otherName...' : 'Connecting...');
      }
    } catch (_) {
      // Network interruptions are handled by the SDK's reconnect logic.
    } finally {
      checking = false;
    }
  }

  Future<void> _connect() async {
    if (connecting || connected || hangingUp) return;
    setState(() {
      connecting = true;
      error = null;
      statusText = 'Connecting to call...';
    });
    try {
      final credentials = await Api.callToken(callId);
      final url = '${credentials['server_url'] ?? ''}'.trim();
      final token = '${credentials['participant_token'] ?? ''}'.trim();
      if (url.isEmpty || token.isEmpty) {
        throw Exception('The call server did not return valid connection credentials.');
      }
      await room.connect(url, token);
      if (!mounted || hangingUp) {
        unawaited(_teardown());
        return;
      }
      final local = room.localParticipant;
      if (local == null) throw Exception('LiveKit connected without a local participant.');
      await local.setMicrophoneEnabled(true);
      if (videoCall) {
        try {
          await local.setCameraEnabled(true);
        } catch (_) {}
      }
      try {
        await Hardware.instance.setSpeakerphoneOn(videoCall);
      } catch (_) {}
      if (!mounted || hangingUp) return;
      connectedAt = DateTime.now();
      clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && connectedAt != null) {
          setState(() => elapsed = DateTime.now().difference(connectedAt!));
        }
      });
      setState(() {
        connected = true;
        connecting = false;
        statusText = 'Connected';
        speaker = videoCall;
        cameraEnabled = videoCall;
      });
    } catch (e) {
      if (!mounted || hangingUp) return;
      setState(() {
        connecting = false;
        error = 'We could not connect the call. Check your connection and try again.';
        statusText = 'Could not connect';
      });
    }
  }

  void _refreshRoom() {
    if (mounted && !hangingUp) setState(() {});
  }

  VideoTrack? _videoFor(Participant? participant, {required bool remote}) {
    if (participant == null) return null;
    for (final publication in participant.videoTrackPublications) {
      if (publication.source == TrackSource.screenShareVideo) continue;
      if (remote && !publication.subscribed) continue;
      if (publication.muted) continue;
      final track = publication.track;
      if (track is VideoTrack) return track;
    }
    return null;
  }

  // -------------------------------------------------------------- controls

  Future<void> _toggleMic() async {
    try {
      final local = room.localParticipant;
      if (local == null) return;
      await local.setMicrophoneEnabled(muted);
      if (mounted) setState(() => muted = !muted);
    } catch (_) {
      _showError('Could not change microphone settings. Please try again.');
    }
  }

  Future<void> _toggleCamera() async {
    try {
      final local = room.localParticipant;
      if (local == null) return;
      await local.setCameraEnabled(!cameraEnabled);
      if (mounted) setState(() => cameraEnabled = !cameraEnabled);
    } catch (_) {
      _showError('Could not change camera settings. Please try again.');
    }
  }

  Future<void> _toggleSpeaker() async {
    try {
      await Hardware.instance.setSpeakerphoneOn(!speaker);
      if (mounted) setState(() => speaker = !speaker);
    } catch (_) {
      _showError('Audio routing could not be changed.');
    }
  }

  void _showError(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    clockTimer?.cancel();
    room.removeListener(_refreshRoom);
    listener.dispose();
    // If the route was removed some other way, still end everything.
    if (!hangingUp) {
      hangingUp = true;
      unawaited(_notifyServerCallEnded());
    }
    unawaited(_teardown());
    super.dispose();
  }

  // ------------------------------------------------------------------- UI

  String get _clock {
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return elapsed.inHours > 0 ? '${elapsed.inHours}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final remoteParticipants = room.remoteParticipants.values.toList();
    final remote = remoteParticipants.isEmpty ? null : remoteParticipants.first;
    final remoteTrack = hangingUp ? null : _videoFor(remote, remote: true);
    final localTrack = hangingUp ? null : _videoFor(room.localParticipant, remote: false);
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 560;
    final pipW = (size.shortestSide * .28).clamp(96.0, 170.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0B1C),
        body: Stack(fit: StackFit.expand, children: [
          // Background / remote video
          if (videoCall && remoteTrack != null)
            VideoTrackRenderer(remoteTrack, fit: VideoViewFit.cover)
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2B1A5C), Color(0xFF100D1F)],
                ),
              ),
            ),
          SafeArea(
            child: Column(children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                child: Row(children: [
                  IconButton(
                    tooltip: 'End call',
                    onPressed: _hangUp,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(otherName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(connected ? _clock : statusText,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.lock_rounded, size: 13, color: connected ? const Color(0xFF4ADE80) : Colors.white54),
                      const SizedBox(width: 5),
                      Text(videoCall ? 'Video' : 'Audio',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]),
              ),
              // Stage
              Expanded(
                child: Stack(children: [
                  if (!(videoCall && remoteTrack != null))
                    Center(
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: OsColors.brandGradient,
                              boxShadow: [
                                BoxShadow(
                                    color: OsColors.purpleDeep.withValues(alpha: connected ? .55 : .3),
                                    blurRadius: connected ? 40 : 20),
                              ],
                            ),
                            child: AvatarPhoto(user: otherUser, radius: compact ? 44 : 66),
                          ),
                          SizedBox(height: compact ? 10 : 20),
                          Text(otherName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text(
                            connected
                                ? (videoCall ? 'Waiting for their video...' : 'OS audio call')
                                : statusText,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          if (!connected && error == null) ...[
                            const SizedBox(height: 18),
                            const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                          ],
                        ]),
                      ),
                    ),
                  if (videoCall && localTrack != null && cameraEnabled)
                    Positioned(
                      right: 16,
                      top: 8,
                      width: pipW,
                      height: pipW * 1.4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(border: Border.all(color: Colors.white24, width: 1.5)),
                          child: VideoTrackRenderer(localTrack, fit: VideoViewFit.cover),
                        ),
                      ),
                    ),
                  if (error != null)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 12,
                      child: Material(
                        color: const Color(0xFF3B2025),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 10),
                            FilledButton(
                              onPressed: connecting ? null : _connect,
                              child: const Text('Retry connection'),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              // Controls
              Container(
                margin: EdgeInsets.fromLTRB(16, 8, 16, compact ? 8 : 20),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .38),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white12),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _control(
                        icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: muted ? 'Unmute' : 'Mute',
                        active: muted,
                        onTap: connected ? _toggleMic : null,
                      ),
                      if (videoCall)
                        _control(
                          icon: cameraEnabled ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                          label: 'Camera',
                          active: !cameraEnabled,
                          onTap: connected ? _toggleCamera : null,
                        ),
                      _control(
                        icon: speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
                        label: speaker ? 'Speaker' : 'Earpiece',
                        active: speaker,
                        onTap: connected ? _toggleSpeaker : null,
                      ),
                      _control(
                        icon: Icons.call_end_rounded,
                        label: 'End',
                        color: const Color(0xFFE54555),
                        big: true,
                        onTap: _hangUp,
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _control({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool active = false,
    bool big = false,
    Color? color,
  }) {
    final bg = color ?? (active ? Colors.white : Colors.white.withValues(alpha: .16));
    final fg = color != null ? Colors.white : (active ? const Color(0xFF1B1730) : Colors.white);
    final d = big ? 68.0 : 56.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: d,
        height: d,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: Colors.white.withValues(alpha: .08),
            disabledForegroundColor: Colors.white30,
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
          ),
          child: Icon(icon, size: big ? 30 : 24),
        ),
      ),
      const SizedBox(height: 7),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}
