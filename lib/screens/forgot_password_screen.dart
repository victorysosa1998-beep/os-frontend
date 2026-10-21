import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';

/// Password recovery: request email OTP, verify it by resetting the password.
/// OTP validity and attempt limits are enforced by the backend.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _otp = List.generate(6, (_) => TextEditingController());
  final _otpFocus = List.generate(6, (_) => FocusNode());
  final _formKey = GlobalKey<FormState>();
  bool _sent = false, _busy = false, _obscure = true;
  String? _error, _notice;
  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void initState() { super.initState(); _email.text = widget.initialEmail; }
  @override
  void dispose() {
    _timer?.cancel(); _email.dispose(); _password.dispose(); _confirm.dispose();
    for (final c in _otp) { c.dispose(); }
    for (final f in _otpFocus) { f.dispose(); }
    super.dispose();
  }

  String get _code => _otp.map((c) => c.text).join();
  void _startCooldown() {
    _timer?.cancel(); setState(() => _resendSeconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_resendSeconds <= 1) { timer.cancel(); setState(() => _resendSeconds = 0); }
      else { setState(() => _resendSeconds--); }
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (_busy) return;
    final address = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      setState(() => _error = 'Enter a valid email address.'); return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await Api.sendPasswordReset(address);
      if (!mounted) return;
      setState(() { _sent = true; _notice = 'If this email belongs to an active account, a code has been sent. Check your inbox and spam folder.'; });
      _startCooldown();
      if (!resend) _otpFocus.first.requestFocus();
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _reset() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    if (_code.length != 6 || _otp.any((c) => c.text.length != 1)) {
      setState(() => _error = 'Enter all 6 digits from the email.'); return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await Api.confirmPasswordReset(_email.text.trim(), _code, _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  InputDecoration _dec(String label) => InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24), child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440), child: Form(
            key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.lock_reset_rounded, size: 58),
              const SizedBox(height: 18),
              Text(_sent ? 'Check your email' : 'Forgot your password?', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_sent ? 'Enter the six-digit verification code, then choose a new password.' : 'We’ll email you a one-time code to securely reset your password.', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextFormField(controller: _email, enabled: !_busy && !_sent, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: _dec('Email address'), validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Enter a valid email address' : null),
              if (_sent) ...[
                const SizedBox(height: 22),
                const Text('Verification code', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: List.generate(6, (i) => Expanded(child: Padding(padding: EdgeInsets.only(right: i == 5 ? 0 : 7), child: TextField(
                  controller: _otp[i], focusNode: _otpFocus[i], enabled: !_busy, textAlign: TextAlign.center, keyboardType: TextInputType.number, maxLength: 1,
                  autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
                  decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
                  onChanged: (v) { if (v.length > 1) { _otp[i].text = v.substring(v.length - 1); _otp[i].selection = TextSelection.collapsed(offset: _otp[i].text.length); } if (v.isNotEmpty && i < 5) _otpFocus[i + 1].requestFocus(); if (v.isEmpty && i > 0) _otpFocus[i - 1].requestFocus(); setState(() {}); },
                ))))),
                const SizedBox(height: 20),
                TextFormField(controller: _password, enabled: !_busy, obscureText: _obscure, decoration: _dec('New password').copyWith(helperText: 'At least 10 characters', suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (v) => (v == null || v.length < 10) ? 'Use at least 10 characters' : null),
                const SizedBox(height: 14),
                TextFormField(controller: _confirm, enabled: !_busy, obscureText: true, decoration: _dec('Confirm new password'), validator: (v) => v != _password.text ? 'Passwords do not match' : null),
                Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _busy || _resendSeconds > 0 ? null : () => _sendCode(resend: true), child: Text(_resendSeconds > 0 ? 'Resend code in ${_resendSeconds}s' : 'Resend code'))),
              ],
              if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: theme.colorScheme.error))],
              if (_notice != null) ...[const SizedBox(height: 12), Text(_notice!, style: TextStyle(color: theme.colorScheme.primary))],
              const SizedBox(height: 18),
              FilledButton.icon(onPressed: _busy ? null : (_sent ? _reset : () { if (_formKey.currentState?.validate() ?? false) _sendCode(); }), icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_sent ? Icons.check_circle_outline : Icons.mail_outline), label: Text(_busy ? 'Please wait…' : (_sent ? 'Reset password' : 'Send verification code'))),
              if (_sent) TextButton(onPressed: _busy ? null : () => setState(() { _sent = false; _error = null; _notice = null; }), child: const Text('Use a different email address')),
            ]),
          ),
        ),
      ))),
    );
  }
}
