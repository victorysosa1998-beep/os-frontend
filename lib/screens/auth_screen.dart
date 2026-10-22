import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/biometric_auth_service.dart';

import '../services/api.dart';
import 'forgot_password_screen.dart';
import '../data/nigerian_states.dart';
import '../theme/app_theme.dart';
import '../theme/os_ui.dart';
import '../theme/os_buttons.dart';
import '../theme/os_cartoon.dart';
import '../theme/user_badge.dart';

class AuthScreen extends StatefulWidget {
  final void Function(Map<String, dynamic>) onDone;

  const AuthScreen({
    super.key,
    required this.onDone,
  });

  @override
  State<AuthScreen> createState() => _AuthState();
}

class _AuthState extends State<AuthScreen> {
  final GlobalKey<FormState> form = GlobalKey<FormState>();

  final TextEditingController email = TextEditingController();
  final TextEditingController pass = TextEditingController();
  final TextEditingController name = TextEditingController();
  final TextEditingController city = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController dob = TextEditingController();

  bool login = true;
  bool busy = false;
  bool obscure = true;
  bool enableBiometric = false;
  bool biometricEnabled = false;
  String? biometricEmail; // the ONE account fingerprint is set for on this device

  String get _typedEmail => email.text.trim().toLowerCase();

  /// Fingerprint icon is only offered for the account it was set up for.
  bool get _bioForThisEmail =>
      biometricEnabled && biometricEmail != null && _typedEmail == biometricEmail;

  Future<void> _storeBioEmail(String? e) async {
    final prefs = await SharedPreferences.getInstance();
    if (e == null) {
      await prefs.remove('os_biometric_email');
    } else {
      await prefs.setString('os_biometric_email', e);
    }
    biometricEmail = e;
  }

  Future<void> _clearBio() async {
    await Api.setBiometricLoginEnabled(false);
    await _storeBioEmail(null);
  }

  void _syncTickToEmail() {
    // Matching account: icon mode (tick state stays "on" so a password
    // sign-in never switches it off). Any other email: tick starts unchecked.
    setState(() => enableBiometric = _bioForThisEmail);
  }

  String gender = 'female';
  String? error;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
    _loadBiometricSetting();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('os_last_email');
    if (mounted) setState(() {
      if (email.text.isEmpty && saved != null) email.text = saved;
      biometricEnabled = prefs.getBool('os_biometric_enabled') ?? false;
      var bound = prefs.getString('os_biometric_email');
      // Older installs: fingerprint was set before accounts were tracked.
      if (biometricEnabled && bound == null && saved != null) {
        bound = saved.trim().toLowerCase();
        prefs.setString('os_biometric_email', bound);
      }
      biometricEmail = bound;
      enableBiometric = _bioForThisEmail;
    });
  }

  Future<void> _loadBiometricSetting() async {
    final enabled = await Api.biometricLoginEnabled();
    if (mounted) setState(() { biometricEnabled = enabled; enableBiometric = _bioForThisEmail; });
  }

  Future<void> _loginWithBiometric() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final hasToken = await Api.token();
      if (hasToken == null || hasToken.isEmpty) {
        await Api.setBiometricLoginEnabled(false);
        if (mounted) setState(() { biometricEnabled = false; enableBiometric = false; error = 'Your saved session has expired. Sign in with your password first.'; });
        return;
      }
      final authenticated = await BiometricAuthService.authenticate();
      if (!authenticated) {
        if (mounted) setState(() => error = 'Fingerprint verification was cancelled or unavailable. You can sign in with your password.');
        return;
      }
      final user = await Api.me();
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('os_last_email', email.text.trim());
      widget.onDone(user);
    } catch (e) {
      if (e is ApiException && e.isAuth) {
        await Api.logout();
        if (mounted) setState(() { biometricEnabled = false; enableBiometric = false; });
      }
      if (!mounted) return;
      setState(() => error = 'Could not restore your session. Please sign in with your password.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    name.dispose();
    city.dispose();
    phone.dispose();
    dob.dispose();
    super.dispose();
  }

  String? validateEmail(String? value) {
    final input = value?.trim() ?? '';
    final emailPattern =
        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (input.isEmpty || !emailPattern.hasMatch(input)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.length < 10) {
      return 'Use at least 10 characters';
    }

    return null;
  }

  String? validateDateOfBirth(String? value) {
    final input = value?.trim() ?? '';

    if (input.isEmpty) {
      return 'Enter your date of birth';
    }

    final parsed = DateTime.tryParse(input);

    if (parsed == null ||
        parsed.year < 1900 ||
        parsed.isAfter(DateTime.now()) ||
        parsed.year.toString().padLeft(4, '0') !=
            input.split('-').first) {
      return 'Use YYYY-MM-DD format';
    }

    // DateTime.tryParse can normalize some invalid dates.
    final parts = input.split('-');
    if (parts.length != 3 ||
        parts[0].length != 4 ||
        parts[1].length != 2 ||
        parts[2].length != 2 ||
        parsed.year.toString().padLeft(4, '0') != parts[0] ||
        parsed.month.toString().padLeft(2, '0') != parts[1] ||
        parsed.day.toString().padLeft(2, '0') != parts[2]) {
      return 'Enter a valid date in YYYY-MM-DD format';
    }

    final today = DateTime.now();
    var age = today.year - parsed.year;

    if (today.month < parsed.month ||
        (today.month == parsed.month && today.day < parsed.day)) {
      age--;
    }

    if (age < 18) {
      return 'You must be at least 18 to join OS';
    }

    return null;
  }


  Future<void> go() async {
    FocusScope.of(context).unfocus();

    if (busy) return;

    if (!(form.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final Map<String, dynamic> user;

      if (login) {
        user = await Api.login(
          email.text.trim(),
          pass.text,
        );
      } else {
        user = await Api.signup({
          'email': email.text.trim(),
          'password': pass.text,
          'display_name': name.text.trim(),
          'gender': gender,
          'date_of_birth': dob.text.trim(),
          'city': city.text.trim(),
          'phone': phone.text.trim(),
        });
      }

      if (!mounted) return;

      final alreadyBound = _bioForThisEmail;

      // Signing up or in as a different account replaces the saved session, so
      // the old fingerprint binding no longer applies (one account per device).
      if ((!login || !enableBiometric) && biometricEnabled) {
        await _clearBio();
        if (mounted) setState(() => biometricEnabled = false);
      }

      if (login && enableBiometric && !alreadyBound) {
        final available = await BiometricAuthService.isAvailable();
        if (!available) {
          await _clearBio();
          if (mounted) setState(() { biometricEnabled = false; enableBiometric = false; });
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fingerprint authentication is not set up on this device. You are still signed in.')),
          );
        } else {
          final verified = await BiometricAuthService.authenticate(
            reason: 'Confirm fingerprint login for OS Dating',
          );
          if (verified) {
            await Api.setBiometricLoginEnabled(true);
            await _storeBioEmail(email.text.trim().toLowerCase());
            if (mounted) setState(() => biometricEnabled = true);
          } else {
            await _clearBio();
            if (mounted) setState(() { biometricEnabled = false; enableBiometric = false; });
          }
        }
      }

      // Email verification is mandatory: main.dart shows EmailVerificationGate until
      // the member enters the code, and the backend refuses other requests until then.

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('os_last_email', email.text.trim());
      widget.onDone(user);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = e
            .toString()
            .replaceFirst(RegExp(r'^Exception:\s*'), '')
            .trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> resetPassword() async {
    final targetEmail = email.text.trim();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(initialEmail: targetEmail),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        login = true;
        pass.clear();
        error = 'Password reset successfully. Sign in with your new password.';
      });
    }
  }

  InputDecoration dec(String label) {
    return InputDecoration(labelText: label);
  }

  void toggleMode() {
    if (busy) return;

    setState(() {
      login = !login;
      error = null;
      form.currentState?.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: OsBackground(
        child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                    const _AuthHero(),
                    const SizedBox(height: 22),
                  ] else ...[
                    const _Brand(),
                    const SizedBox(height: 14),
                  ],
                  _ModeToggle(
                    login: login,
                    onChanged: (wantLogin) {
                      if (wantLogin != login) toggleMode();
                    },
                  ),
                  const SizedBox(height: 22),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: Column(
                      key: ValueKey(login),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          login ? 'Welcome back.' : 'Create your OS account.',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          login
                              ? 'Your people are waiting.'
                              : 'Real people. Real moments. Real connections.',
                          style: const TextStyle(color: OsColors.muted, fontSize: 14.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  if (error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: OsColors.coral.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: OsColors.coral.withValues(alpha: .35)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.error_outline_rounded, color: OsColors.coral, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(color: OsColors.coral, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ]),
                    ),
                  ],

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: OsColors.surface.withValues(alpha: .72),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: OsColors.border.withValues(alpha: .8)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .25),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Material(
                    color: Colors.transparent,
                    child: Form(
                    key: form,
                    child: Column(
                      children: [
                        if (!login) ...[
                          TextFormField(
                            controller: name,
                            textCapitalization: TextCapitalization.words,
                            enabled: !busy,
                            decoration: dec('Display name'),
                            validator: (value) {
                              if (value == null ||
                                  value.trim().length < 2) {
                                return 'Enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!login) ...[
                          TextFormField(
                            controller: phone,
                            enabled: !busy,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: dec('Phone number (optional, include country code)'),
                            validator: (value) {
                              final valueText = value?.trim() ?? '';
                              if (valueText.isNotEmpty && valueText.replaceAll(RegExp(r'[^0-9]'), '').length < 7) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],

                        TextFormField(
                          controller: email,
                          enabled: !busy,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: dec('Email'),
                          onChanged: (_) => _syncTickToEmail(),
                          validator: validateEmail,
                        ),
                        const SizedBox(height: 12),

                        TextFormField(
                          controller: pass,
                          enabled: !busy,
                          obscureText: obscure,
                          textInputAction: login
                              ? TextInputAction.done
                              : TextInputAction.next,
                          autofillHints: [
                            login
                                ? AutofillHints.password
                                : AutofillHints.newPassword,
                          ],
                          onFieldSubmitted: (_) {
                            if (login) go();
                          },
                          decoration: dec('Password').copyWith(
                            suffixIcon: IconButton(
                              tooltip: obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () {
                                setState(() {
                                  obscure = !obscure;
                                });
                              },
                              icon: Icon(
                                obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: validatePassword,
                        ),

                        if (!login) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: dob,
                            enabled: !busy,
                            keyboardType: TextInputType.datetime,
                            decoration: dec(
                              'Date of birth (YYYY-MM-DD)',
                            ).copyWith(
                              hintText: '2000-05-21',
                              suffixIcon: IconButton(
                                tooltip: 'Choose date',
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final now = DateTime.now();
                                        final latest = DateTime(
                                          now.year - 18,
                                          now.month,
                                          now.day,
                                        );

                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: latest,
                                          firstDate: DateTime(1900),
                                          lastDate: latest,
                                          helpText: 'Date of birth',
                                        );

                                        if (picked != null && mounted) {
                                          dob.text =
                                              '${picked.year.toString().padLeft(4, '0')}-'
                                              '${picked.month.toString().padLeft(2, '0')}-'
                                              '${picked.day.toString().padLeft(2, '0')}';
                                        }
                                      },
                                icon: const Icon(
                                  Icons.calendar_month_outlined,
                                ),
                              ),
                            ),
                            validator: validateDateOfBirth,
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: gender,
                            decoration: dec('Gender'),
                            items: const [
                              DropdownMenuItem(
                                value: 'female',
                                child: Text('Female'),
                              ),
                              DropdownMenuItem(
                                value: 'male',
                                child: Text('Male'),
                              ),
                            ],
                            onChanged: busy
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        gender = value;
                                      });
                                    }
                                  },
                          ),
                          const SizedBox(height: 12),

                          DropdownButtonFormField<String>(
                            value: nigerianStates.contains(city.text) ? city.text : null,
                            decoration: dec('State / FCT'),
                            isExpanded: true,
                            items: nigerianStates.map((state) => DropdownMenuItem<String>(
                              value: state, child: Text(state),
                            )).toList(),
                            onChanged: busy ? null : (value) {
                              if (value != null) setState(() => city.text = value);
                            },
                            validator: (value) => (value == null || value.isEmpty)
                                ? 'Select your state or the FCT' : null,
                          ),
                        ],

                        const SizedBox(height: 22),
                        OsGradientButton(
                          label: login ? 'Sign in' : 'Join OS',
                          icon: login ? Icons.arrow_forward_rounded : Icons.favorite_rounded,
                          busy: busy,
                          onPressed: go,
                        ),
                        if (login) ...[
                          if (!_bioForThisEmail) CheckboxListTile(
                            contentPadding: EdgeInsets.zero, dense: true, visualDensity: VisualDensity.compact,
                            value: enableBiometric,
                            onChanged: busy ? null : (value) => setState(() => enableBiometric = value ?? false),
                            title: const Text('Use fingerprint login', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            subtitle: const Text('Needs a fingerprint set up on this phone', style: TextStyle(fontSize: 12, color: OsColors.muted)),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          if (_bioForThisEmail) ...[
                            const SizedBox(height: 16),
                            Center(
                              child: Opacity(
                                opacity: busy ? .5 : 1,
                                child: OsPressable(
                                  scale: .9,
                                  onTap: busy ? null : _loginWithBiometric,
                                  child: Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: OsColors.brandGradient,
                                      border: Border.all(color: Colors.white.withValues(alpha: .18)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: OsColors.purpleDeep.withValues(alpha: .45),
                                          blurRadius: 22,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 42),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : resetPassword, child: const Text('Forgot password?'))),
                        ],
                      ],
                    ),
                  ),
                  ),
                  ),

                  const SizedBox(height: 14),
                  OsButton(
                    kind: OsBtnKind.ghost,
                    label: login
                        ? 'New here? Create an account'
                        : 'I already have an account',
                    onPressed: busy ? null : toggleMode,
                  ),
                  if (login) const _TrustRow(),

                  if (!login)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'By joining OS, you confirm you are 18 or older, '
                        'agree to our community rules, and understand '
                        'that verification media is reviewed privately '
                        'by authorized moderators.',
                        style: TextStyle(
                          color: OsColors.muted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
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

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const OsLogo(size: 58);
}

/// Animated illustrated hero with the logo, shown above the form.
class _AuthHero extends StatelessWidget {
  const _AuthHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Stack(children: [
        const Positioned.fill(
          child: CartoonSceneView(
            scene: CartoonScene.discover,
            borderRadius: BorderRadius.all(Radius.circular(30)),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: .55), Colors.transparent],
              ),
            ),
          ),
        ),
        const Positioned(left: 18, bottom: 16, child: OsLogo(size: 48)),
      ]),
    );
  }
}

/// Sign in / Join OS segmented switch.
class _ModeToggle extends StatelessWidget {
  final bool login;
  final ValueChanged<bool> onChanged;
  const _ModeToggle({required this.login, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, bool value) {
      final selected = login == value;
      return Expanded(
        child: OsPressable(
          scale: .97,
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: selected ? OsColors.brandGradient : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                color: selected ? Colors.white : OsColors.muted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OsColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OsColors.border),
      ),
      child: Row(children: [seg('Sign in', true), seg('Join OS', false)]),
    );
  }
}

/// Three small reassurance chips under the sign-in form.
class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, String text) => Expanded(
          child: Column(children: [
            Icon(icon, size: 20, color: OsColors.purple),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: OsColors.muted, fontWeight: FontWeight.w700),
            ),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(children: [
        chip(Icons.verified_rounded, 'Verified\nmembers'),
        chip(Icons.lock_rounded, 'Private by\ndesign'),
        chip(Icons.favorite_rounded, 'Real\nconnections'),
      ]),
    );
  }
}