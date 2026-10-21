import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';

/// Full-screen gate shown until a member verifies their email with the 6-digit
/// code. The backend also refuses every other request until verification is done.
class EmailVerificationGate extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onVerified;
  final VoidCallback onLogout;

  const EmailVerificationGate({
    super.key,
    required this.user,
    required this.onVerified,
    required this.onLogout,
  });

  @override
  State<EmailVerificationGate> createState() => _EmailVerificationGateState();
}

class _EmailVerificationGateState extends State<EmailVerificationGate> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _sending = false;
  String? _error;
  String? _notice;
  int _cooldown = 0;
  Timer? _timer;

  String get _email => '${widget.user['email'] ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    if (widget.user['_email_verification_sent'] == true) {
      _notice = 'We sent a 6-digit code to $_email. Check your inbox and spam folder.';
      _startCooldown(60);
    } else {
      // Existing members, or a signup whose email failed: send a code now.
      WidgetsBinding.instance.addPostFrameCallback((_) => _send());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String _clean(Object e) => '$e'.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();

  Future<void> _send() async {
    if (_sending || _email.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
      _notice = null;
    });
    try {
      await Api.sendEmailVerification(_email);
      if (!mounted) return;
      setState(() => _notice = 'We sent a 6-digit code to $_email. Check your inbox and spam folder.');
      _startCooldown(60);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.confirmEmailVerification(_email, code);
      if (!mounted) return;
      widget.onVerified();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _clean(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OsBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(26),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: OsColors.brandGradient,
                          boxShadow: [
                            BoxShadow(
                              color: OsColors.purpleDeep.withValues(alpha: .45),
                              blurRadius: 36,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.mark_email_unread_rounded, size: 44, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Verify your email',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-digit code we sent to\n$_email\nto continue to OS.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: OsColors.muted, height: 1.5),
                    ),
                    const SizedBox(height: 26),
                    TextField(
                      controller: _code,
                      enabled: !_busy,
                      autofocus: false,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 10),
                      decoration: const InputDecoration(counterText: '', hintText: '------'),
                      onChanged: (v) {
                        if (v.length == 6 && !_busy) _verify();
                      },
                      onSubmitted: (_) => _verify(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                    ],
                    if (_notice != null && _error == null) ...[
                      const SizedBox(height: 10),
                      Text(_notice!, textAlign: TextAlign.center, style: const TextStyle(color: OsColors.muted, fontSize: 12)),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _busy ? null : _verify,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Verify and continue'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: (_busy || _sending || _cooldown > 0) ? null : _send,
                      child: Text(
                        _sending
                            ? 'Sending...'
                            : _cooldown > 0
                                ? 'Resend code in ${_cooldown}s'
                                : 'Resend code',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : widget.onLogout,
                      child: const Text('Wrong email? Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}