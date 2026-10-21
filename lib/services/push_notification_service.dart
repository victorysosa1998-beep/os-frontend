import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'api.dart';

/// FCM delivery and foreground notification display for OS.
/// Incoming-call acceptance still happens through the authenticated FastAPI API.
@pragma('vm:entry-point')
Future<void> osFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification payloads are displayed by the OS when app is backgrounded.
  // Do not accept a call from a push payload; fetch/validate it from FastAPI.
}

class PushNotificationService {
  PushNotificationService._();
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static bool _configured = false;
  static bool _refreshListening = false;

  static Future<void> configure() async {
    if (_configured) return;
    _configured = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android, iOS: DarwinInitializationSettings());
    await _local.initialize(settings);
    const channel = AndroidNotificationChannel(
      'os_calls', 'OS Calls',
      description: 'Incoming audio and video calls',
      importance: Importance.max,
      playSound: true,
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    const general = AndroidNotificationChannel(
      'os_general', 'OS Notifications',
      description: 'OS account and activity notifications',
      importance: Importance.high,
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(general);

    FirebaseMessaging.onBackgroundMessage(osFirebaseBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      // Opening OS resumes the authenticated app; AppShell then fetches the pending call.
      debugPrint('OS push opened: ${message.data['type']}');
    });
    if (!_refreshListening) {
      _refreshListening = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (await Api.token() == null) return;
        try { await Api.registerPushToken(token, platform: _platform); final prefs = await SharedPreferences.getInstance(); await prefs.setString('os_fcm_token', token); } catch (e) { debugPrint('FCM token refresh sync failed: $e'); }
      });
    }
  }

  /// Removes the "Incoming call" notification for [callId] (shown by FCM or locally
  /// with tag os-call-<id>). Call when the call is answered, declined or over.
  static Future<void> clearCallNotification(Object? callId) async {
    if (callId == null) return;
    try { await _local.cancel(0, tag: 'os-call-$callId'); } catch (_) {}
  }

  static String get _platform => Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'unknown';

  static Future<void> registerForSignedInUser() async {
    try {
      await configure();
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('OS notification permission denied by user');
        return;
      }
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await Api.registerPushToken(token, platform: _platform);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('os_fcm_token', token);
      }
    } catch (e) {
      // App login should remain usable even if notification setup is incomplete.
      debugPrint('OS push registration failed: $e');
    }
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    final isCall = message.data['type'] == 'incoming_call';
    final title = message.notification?.title ?? (isCall ? 'Incoming call' : 'OS notification');
    final body = message.notification?.body ?? (isCall ? 'Someone is calling you on OS.' : 'You have a new notification.');
    final callId = message.data['call_id'];
    await _local.show(
      callId != null ? 0 : message.hashCode, title, body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isCall ? 'os_calls' : 'os_general',
          isCall ? 'OS Calls' : 'OS Notifications',
          channelDescription: isCall ? 'Incoming audio and video calls' : 'OS account and activity notifications',
          importance: Importance.max,
          priority: Priority.high,
          category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
          fullScreenIntent: isCall,
          playSound: true,
          tag: callId != null ? 'os-call-$callId' : null,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
      payload: message.data['call_id'],
    );
  }
}