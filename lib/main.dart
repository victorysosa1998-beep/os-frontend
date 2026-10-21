import 'dart:async';
import 'package:flutter/material.dart';
import 'package:os_dating/email_verification_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/os_layout.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/app_shell.dart';

import 'theme/user_badge.dart';
import 'services/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await PushNotificationService.configure();
  runApp(const OsApp());
}

class OsApp extends StatelessWidget {
  const OsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'OS — Real Connections',
        theme: buildOsTheme(),
        // Clamps text scaling and caps content width on tablets / desktop.
        builder: (context, child) => OsAppFrame(child: child),
        home: const Entry(),
      );
}

/// Flow: Welcome → Splash (session check runs underneath)
///       → signed in?  Admin / App shell
///       → first launch? Onboarding → Auth
///       → otherwise Auth
class Entry extends StatefulWidget {
  const Entry({super.key});

  @override
  State<Entry> createState() => _EntryState();
}

class _EntryState extends State<Entry> with WidgetsBindingObserver {
  static const _onboardedKey = 'os_onboarded';

  late final Future<void> ready;
  bool introDone = false;
  bool onboarded = true;
  Map<String, dynamic>? user;
  Timer? _inactivityTimer;
  DateTime? _backgroundedAt;
  static const Duration _inactivityLimit = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ready = _load();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (user == null) return;
    _inactivityTimer = Timer(_inactivityLimit, () {
      if (mounted && user != null) _expireForInactivity();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (user == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= _inactivityLimit) {
        _expireForInactivity();
      } else {
        _resetInactivityTimer();
      }
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      onboarded = prefs.getBool(_onboardedKey) ?? false;
      final savedToken = await Api.token();
      final biometricEnabled = await Api.biometricLoginEnabled();
      // When biometric login is enabled, never restore the protected app silently.
      if (savedToken != null && savedToken.isNotEmpty && !biometricEnabled) { user = await Api.me(); await PushNotificationService.registerForSignedInUser(); _resetInactivityTimer(); }
    } on ApiException catch (e) {
      // Only drop the session if the server rejected it, not on network errors.
      if (e.isAuth) await Api.logout();
    } catch (_) {}
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
    if (mounted) setState(() => onboarded = true);
  }

  bool _needsEmailGate(Map<String, dynamic> u) => !isAdminUser(u) && u['email_verified'] != true;

  Future<void> _emailVerified() async {
    final current = user;
    if (current == null) return;
    Map<String, dynamic> next = {...current, 'email_verified': true};
    try {
      next = await Api.me();
    } catch (_) {}
    if (!mounted) return;
    setState(() => user = next);
  }

  void signed(Map<String, dynamic> u) {
    setState(() => user = u);
    _resetInactivityTimer();
    PushNotificationService.registerForSignedInUser();
  }

  Future<void> _expireForInactivity() async {
    _inactivityTimer?.cancel();
    await Api.logout(preserveBiometricSession: true);
    if (mounted) setState(() => user = null);
  }

  Future<void> logout() async {
    _inactivityTimer?.cancel();
    await Api.logout();
    if (mounted) setState(() => user = null);
  }

  @override
  Widget build(BuildContext context) {
    Widget page;
    if (!introDone) {
      page = IntroSequence(
        key: const ValueKey('intro'),
        ready: ready,
        onFinished: () => setState(() => introDone = true),
      );
    } else if (user == null) {
      page = onboarded
          ? AuthScreen(key: const ValueKey('auth'), onDone: signed)
          : OnboardingScreen(key: const ValueKey('onboarding'), onDone: _finishOnboarding);
    } else if (_needsEmailGate(user!)) {
      page = EmailVerificationGate(
        key: const ValueKey('email-gate'),
        user: user!,
        onVerified: _emailVerified,
        onLogout: logout,
      );
    } else {
        page = AppShell(key: const ValueKey('shell'), user: user!, onLogout: logout);
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: page,
      ),
    );
  }
}