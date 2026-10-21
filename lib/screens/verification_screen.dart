
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';

class VerificationScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final void Function(Map<String, dynamic>) onChanged;

  const VerificationScreen({
    super.key,
    required this.user,
    required this.onChanged,
  });

  @override
  State<VerificationScreen> createState() => _VerificationState();
}

class _VerificationState extends State<VerificationScreen> {
  String status = 'unverified';
  bool busy = false;

  String? liveKey;
  String? photoKey;

  @override
  void initState() {
    super.initState();
    status = widget.user['verification_status']?.toString() ?? 'unverified';
    loadStatus();
  }

  Future<void> loadStatus() async {
    try {
      final data = await Api.verificationStatus();

      if (!mounted) return;

      setState(() {
        status = data['status']?.toString() ?? status;
      });

      widget.onChanged({
        ...widget.user,
        'verification_status': status,
      });
    } catch (_) {
      // Keep the status supplied with the current user if loading fails.
    }
  }

  Future<void> chooseVideo() async {
    if (busy || status == 'verified' || status == 'pending') return;

    setState(() => busy = true);

    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera is available on this device.');
      }

      final frontCamera = cameras.firstWhere(
        (camera) =>
            camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      try {
        await controller.initialize();

        if (!mounted) {
          await controller.dispose();
          return;
        }

        final path = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => LivenessCapture(
              controller: controller,
            ),
          ),
        );

        if (path == null || path.isEmpty || !mounted) return;

        final file = File(path);

        if (!await file.exists()) {
          throw Exception('The recorded video could not be found.');
        }

        final result = await Api.upload(
          file,
          'liveness',
          'video/mp4',
        );

        if (!mounted) return;

        final key = result['object_key']?.toString();

        if (key == null || key.isEmpty) {
          throw Exception('The server did not return a video upload key.');
        }

        setState(() {
          liveKey = key;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liveness video uploaded successfully.'),
          ),
        );
      } finally {
        await controller.dispose();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> choosePhoto() async {
    if (busy || status == 'verified' || status == 'pending') return;

    setState(() => busy = true);

    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );

      if (image == null || !mounted) return;

      final result = await Api.upload(
        File(image.path),
        'verification_photo',
        image.mimeType ?? 'image/jpeg',
      );

      if (!mounted) return;

      final key = result['object_key']?.toString();

      if (key == null || key.isEmpty) {
        throw Exception('The server did not return a photo upload key.');
      }

      setState(() {
        photoKey = key;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comparison photo uploaded successfully.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> submit() async {
    if (busy) return;

    if (status == 'verified') {
      return;
    }

    if (status == 'pending') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your verification is already being reviewed.'),
        ),
      );
      return;
    }

    if (liveKey == null || photoKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the liveness video and comparison photo first.',
          ),
        ),
      );
      return;
    }

    setState(() => busy = true);

    try {
      await Api.submitVerification(liveKey!, photoKey!);

      if (!mounted) return;

      setState(() {
        status = 'pending';
      });

      widget.onChanged({
        ...widget.user,
        'verification_status': 'pending',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Submitted successfully for review.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  String _errorMessage(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final verified = status == 'verified';
    final pending = status == 'pending';
    final rejected = status == 'rejected';

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 28),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: verified
                ? OsColors.purple.withValues(alpha: 0.12)
                : OsColors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Icon(
                verified ? Icons.verified : Icons.shield_outlined,
                color: verified ? OsColors.purple : OsColors.coral,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verified
                          ? 'You are verified'
                          : pending
                              ? 'Verification pending'
                              : rejected
                                  ? 'Verification declined'
                                  : 'Verify your identity',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verified
                          ? 'Your verification is approved.'
                          : pending
                              ? 'Your submission is waiting for moderator review.'
                              : rejected
                                  ? 'Review the feedback and submit fresh evidence.'
                                  : 'Connecting and messaging unlock after approval.',
                      style: const TextStyle(
                        color: OsColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 16),
        ],

        if (pending)
          const _VerificationNotice(
            icon: Icons.hourglass_top,
            title: 'Review in progress',
            text:
                'An authorized OS reviewer will compare your liveness '
                'evidence with your submitted photo. You do not need '
                'to submit again while your review is pending.',
          ),

        if (verified)
          const _VerificationNotice(
            icon: Icons.verified,
            title: 'Identity verified',
            text:
                'Your identity review has been approved. Your account '
                'should now reflect the permissions granted to verified users.',
          ),

        if (!verified && !pending) ...[
          StepCard(
            n: '01',
            title: 'Liveness video',
            text:
                'Record a short video using your camera. Look directly '
                'at the camera and follow the on-screen instructions.',
            done: liveKey != null,
            onTap: chooseVideo,
            enabled: !busy,
          ),
          StepCard(
            n: '02',
            title: 'Comparison photo',
            text:
                'Take a clear, current photo of yourself. It will be '
                'used for identity review.',
            done: photoKey != null,
            onTap: choosePhoto,
            enabled: !busy,
          ),
          StepCard(
            n: '03',
            title: 'Submit for review',
            text:
                'Submit both items for review by authorized moderators.',
            done: false,
            onTap: submit,
            enabled: !busy,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Submit for verification'),
            ),
          ),
        ],

        if (rejected)
          const Padding(
            padding: EdgeInsets.only(top: 15),
            child: Text(
              'Your previous submission was rejected. You can replace '
              'both items and submit again. If the server provides a '
              'rejection reason, display it here.',
              style: TextStyle(
                color: OsColors.coral,
                height: 1.4,
              ),
            ),
          ),

        const SizedBox(height: 20),
        const Text(
          'Privacy matters. Upload verification evidence only through '
          'the official OS app. Access to submitted media should be '
          'restricted to authorized reviewers.',
          style: TextStyle(
            color: OsColors.muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    ));
  }
}

class StepCard extends StatelessWidget {
  final String n;
  final String title;
  final String text;
  final bool done;
  final bool enabled;
  final VoidCallback onTap;

  const StepCard({
    super.key,
    required this.n,
    required this.title,
    required this.text,
    required this.done,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: done
                  ? OsColors.purple.withValues(alpha: 0.2)
                  : OsColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: done
                  ? const Icon(
                      Icons.check,
                      color: OsColors.purple,
                    )
                  : Text(
                      n,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: OsColors.muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: enabled ? onTap : null,
                  child: Text(done ? 'Replace' : 'Start'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationNotice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _VerificationNotice({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 32,
            color: OsColors.purple,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              color: OsColors.muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class LivenessCapture extends StatefulWidget {
  final CameraController controller;

  const LivenessCapture({
    super.key,
    required this.controller,
  });

  @override
  State<LivenessCapture> createState() => _LivenessCaptureState();
}

class _LivenessCaptureState extends State<LivenessCapture> {
  bool recording = false;
  bool finished = false;
  String? error;

  Future<void> startRecording() async {
    if (recording || finished) return;

    setState(() {
      recording = true;
      error = null;
    });

    try {
      await widget.controller.startVideoRecording();

      await Future.delayed(const Duration(seconds: 8));

      if (!mounted) return;

      final video = await widget.controller.stopVideoRecording();

      if (!mounted) return;

      finished = true;
      Navigator.of(context).pop(video.path);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        recording = false;
        error = e
            .toString()
            .replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liveness check'),
      ),
      body: controller.value.isInitialized
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                Positioned(
                  top: 25,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      recording
                          ? 'Recording. Look at the camera and follow the '
                              'instructions naturally.'
                          : 'You will record for 8 seconds. Look at the '
                              'camera, raise one hand, hold for 2 seconds, '
                              'then lower it.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                if (error != null)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 110,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 35,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FilledButton.icon(
                      onPressed: recording ? null : startRecording,
                      icon: Icon(
                        recording ? Icons.circle : Icons.videocam,
                      ),
                      label: Text(
                        recording
                            ? 'Recording…'
                            : 'Start 8-second check',
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(),
            ),
    );
  }
}
