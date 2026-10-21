import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

class ApiException implements Exception {
  final String message;
  final int? status;

  const ApiException(this.message, [this.status]);

  bool get isAuth => status == 401 || status == 403;

  @override
  String toString() => message;
}

class Api {
  static const String baseUrl = AppConfig.apiBaseUrl;
  static const Duration _timeout = Duration(seconds: 20);
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final Map<String, ({String url, DateTime fetchedAt})> _mediaUrlCache = {};
  static const Duration _mediaUrlCacheTtl = Duration(seconds: 90);

  static Future<String?> token() async {
    // Migrate tokens saved by older app versions from preferences to encrypted storage.
    final secure = await _secureStorage.read(key: 'os_token');
    if (secure != null && secure.isNotEmpty) return secure;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('os_token');
    if (legacy != null && legacy.isNotEmpty) {
      await _secureStorage.write(key: 'os_token', value: legacy);
      await prefs.remove('os_token');
    }
    return legacy;
  }

  static Future<void> saveToken(String value) async {
    await _secureStorage.write(key: 'os_token', value: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('os_token');
  }

  static Future<void> logout({bool preserveBiometricSession = false}) async {
    // On inactivity timeout, keep the encrypted token only when biometric login is enabled.
    final prefs = await SharedPreferences.getInstance();
    final biometricEnabled = prefs.getBool('os_biometric_enabled') ?? false;
    if (!preserveBiometricSession || !biometricEnabled) {
      try { await unregisterPushToken(); } catch (_) {}
      await _secureStorage.delete(key: 'os_token');
      await prefs.remove('os_token');
      if (!preserveBiometricSession) await prefs.setBool('os_biometric_enabled', false);
    }
  }

  static Future<bool> biometricLoginEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('os_biometric_enabled') ?? false;
  }

  static Future<void> setBiometricLoginEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('os_biometric_enabled', enabled);
  }

  static Future<void> registerPushToken(String token, {String platform = 'unknown'}) async {
    await request('POST', '/devices/push-token', body: {'token': token, 'platform': platform});
  }

  static Future<void> unregisterPushToken({String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    final value = token ?? prefs.getString('os_fcm_token');
    if (value == null || value.isEmpty) return;
    await request('DELETE', '/devices/push-token', body: {'token': value, 'platform': _platformName()});
    await prefs.remove('os_fcm_token');
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Converts transport/server exceptions into short, human-friendly copy.
  /// Raw socket traces, HTTP status codes and framework details stay out of UI.
  static String friendlyError(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
    final value = error.toString().replaceFirst(RegExp(r'^(Exception|ApiException):\s*'), '').trim();
    final lower = value.toLowerCase();
    if (lower.contains('socketexception') || lower.contains('clientexception') || lower.contains('handshakeexception') || lower.contains('failed host lookup') || lower.contains('connection refused') || lower.contains('connection reset') || lower.contains('http exception')) {
      return 'Could not reach OS right now. Check your internet connection and try again.';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'That took too long. Please check your connection and try again.';
    }
    if (lower.contains('already active') || lower.contains('call with this member')) {
      return 'A previous call is still being cleared. Wait a moment and try again.';
    }
    if (lower.contains('must approve your reveal') || lower.contains('approve your reveal')) {
      return 'This photo is protected. Send a reveal request and wait for approval.';
    }
    if (lower.contains('not verified') || lower.contains('identity-verified')) {
      return 'Both people need identity verification before using this feature.';
    }
    if (lower.contains('403') || lower.contains('not allowed') || lower.contains('forbidden')) {
      return 'You can’t do that right now. Check your permissions or privacy settings.';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'We couldn’t find that item. It may have been removed or is no longer available.';
    }
    if (RegExp(r'http\s*\d{3}').hasMatch(lower) || lower.contains('status code') || lower.contains('500') || lower.contains('internal server error') || lower.contains('traceback') || lower.contains('exception')) {
      return fallback;
    }
    if (value.isEmpty || value.length > 180 || value.contains('{') || value.contains('\\')) return fallback;
    return value;
  }

  static String _detail(dynamic data) {
    if (data is Map) {
      final detail = data['detail'];

      if (detail is String && detail.isNotEmpty) {
        return detail;
      }

      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'].toString();
        }
      }

      if (data['message'] is String) {
        return data['message'].toString();
      }
    }

    return 'Request failed. Please try again.';
  }

  static dynamic _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};

    try {
      return jsonDecode(response.body);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<http.Response> _send(
    Future<http.Response> Function() call,
  ) async {
    try {
      return await call().timeout(_timeout);
    } on SocketException {
      throw const ApiException(
        'Cannot reach the server. Check your connection and try again.',
      );
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the server. Check your connection and try again.',
      );
    }
  }

  static Map<String, String> _headers(
    String? authToken, {
    bool json = true,
  }) {
    return {
      if (json) 'Content-Type': 'application/json',
      if (authToken != null && authToken.isNotEmpty)
        'Authorization': 'Bearer $authToken',
    };
  }

  static Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final authToken = await token();
    final uri = Uri.parse('$baseUrl$path');
    final headers = _headers(authToken);

    final response = await _send(() {
      switch (method.toUpperCase()) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'POST':
          return http.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'PATCH':
          return http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'PUT':
          return http.put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'DELETE':
          return http.delete(uri, headers: headers, body: jsonEncode(body ?? <String, dynamic>{}));
        default:
          throw ArgumentError('Unsupported HTTP method: $method');
      }
    });

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_detail(data), response.statusCode);
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    return <String, dynamic>{};
  }

  static Future<List<dynamic>> list(String path) async {
    final authToken = await token();

    final response = await _send(
      () => http.get(
        Uri.parse('$baseUrl$path'),
        headers: _headers(authToken, json: false),
      ),
    );

    final data = _decode(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_detail(data), response.statusCode);
    }

    if (data is List) return List<dynamic>.from(data);

    // Admin APIs commonly wrap collections as {users: [...]}, {items: [...]},
    // or {data: {users: [...]}}. Do not silently turn those valid responses
    // into an empty member list.
    dynamic candidate = data;
    for (var depth = 0; depth < 3; depth++) {
      if (candidate is List) return List<dynamic>.from(candidate);
      if (candidate is! Map) break;
      dynamic next;
      for (final key in const ['users', 'members', 'items', 'results', 'records', 'data']) {
        if (candidate[key] is List || candidate[key] is Map) {
          next = candidate[key];
          break;
        }
      }
      if (next == null) break;
      candidate = next;
    }
    return candidate is List ? List<dynamic>.from(candidate) : <dynamic>[];
  }

  // Authentication

  static Future<Map<String, dynamic>> signup(
    Map<String, dynamic> body,
  ) async {
    final data = await request('POST', '/auth/signup', body: body);
    final accessToken = data['access_token'];

    if (accessToken is String && accessToken.isNotEmpty) {
      await saveToken(accessToken);
    }

    final user = data['user'];
    final result = user is Map
        ? Map<String, dynamic>.from(user)
        : <String, dynamic>{};
    result['_email_verification_sent'] = data['email_verification_sent'] == true;
    return result;
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final data = await request(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    );

    final accessToken = data['access_token'];

    if (accessToken is String && accessToken.isNotEmpty) {
      await saveToken(accessToken);
    }

    final user = data['user'];
    return user is Map
        ? Map<String, dynamic>.from(user)
        : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> me() => request('GET', '/me');

  static Future<void> sendEmailVerification(String email) async {
    await request('POST', '/auth/email-verification/send', body: {'email': email});
  }
  static Future<void> confirmEmailVerification(String email, String code) async {
    await request('POST', '/auth/email-verification/confirm', body: {'email': email, 'code': code});
  }
  static Future<void> sendPasswordReset(String email) async {
    await request('POST', '/auth/password-reset/send', body: {'email': email});
  }
  static Future<void> confirmPasswordReset(String email, String code, String password) async {
    await request('POST', '/auth/password-reset/confirm', body: {'email': email, 'code': code, 'new_password': password});
  }
  static Future<void> deleteAccount(String password) async {
    await request('DELETE', '/me/account', body: {'password': password});
  }
  // LiveKit call lifecycle. API secrets never leave the Python backend.
  static Future<Map<String, dynamic>> inviteCall(int conversationId, {required bool video}) =>
      request('POST', '/calls/invite', body: {'conversation_id': conversationId, 'call_type': video ? 'video' : 'audio'});

  static Future<List<dynamic>> incomingCalls() => list('/calls/incoming');

  static Future<Map<String, dynamic>> callStatus(int callId) => request('GET', '/calls/$callId');

  static Future<Map<String, dynamic>> acceptCall(int callId) => request('POST', '/calls/$callId/accept');

  static Future<void> declineCall(int callId) async { await request('POST', '/calls/$callId/decline'); }

  static Future<void> endCall(int callId) async { await request('POST', '/calls/$callId/end'); }

  static Future<Map<String, dynamic>> callToken(int callId) => request('POST', '/calls/$callId/token');

  static Future<void> typing(int conversationId, bool isTyping) async {
    await request('POST', '/realtime/typing', body: {'conversation_id': conversationId, 'is_typing': isTyping});
  }
  static Future<bool> otherPersonTyping(int conversationId) async {
    final result = await request('GET', '/realtime/typing/$conversationId');
    return result['is_typing'] == true;
  }

  static Future<Map<String, dynamic>> profile(
    Map<String, dynamic> body,
  ) {
    return request('PATCH', '/me/profile', body: body);
  }

  /// Fetches a user's public profile.
  ///
  /// The backend must expose GET /users/{userId}.
  static Future<Map<String, dynamic>> userProfile(int userId) {
    if (userId <= 0) {
      throw const ApiException('Invalid user ID.');
    }
    return request('GET', '/users/$userId');
  }

  // Feed and discovery

  static Future<List<dynamic>> feed(String gender) {
    return list('/feed?gender=${Uri.encodeQueryComponent(gender)}');
  }

  static Future<List<dynamic>> discover({
    String gender = 'all',
    String q = '',
    String city = '',
    bool nearby = false,
    double radiusKm = 100,
    double? latitude,
    double? longitude,
  }) {
    final query = <String, String>{
      'gender': gender,
      'q': q,
      'city': city,
      'nearby': nearby.toString(),
      'radius_km': radiusKm.toString(),
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };

    return list('/discover?${Uri(queryParameters: query).query}');
  }

  static Future<Map<String, dynamic>> createPost(
    String text,
    String? mediaKey,
  ) {
    return request(
      'POST',
      '/posts',
      body: {'text': text, 'media_key': mediaKey},
    );
  }

  static Future<void> deletePost(int postId) async {
    await request('DELETE', '/posts/$postId');
  }

  static Future<List<dynamic>> userPosts(int userId) {
    return list('/users/$userId/posts');
  }

  // Persistent post likes

  static Future<Map<String, dynamic>> likePost(int postId) {
    return request('POST', '/posts/$postId/like');
  }

  static Future<Map<String, dynamic>> unlikePost(int postId) {
    return request('DELETE', '/posts/$postId/like');
  }

  // Post comments

  static Future<List<dynamic>> postComments(int postId) {
    return list('/posts/$postId/comments');
  }

  /// Optional status context can be supplied once the backend supports it.
  static Future<Map<String, dynamic>> addComment(
    int postId,
    String body, {
    bool sendToDm = false,
  }) {
    return request(
      'POST',
      '/posts/$postId/comments',
      body: {
        'body': body,
        if (sendToDm) 'send_to_dm': true,
      },
    );
  }

  // Media uploads and downloads

  static Future<Map<String, dynamic>> upload(
    File file,
    String purpose,
    String contentType,
  ) async {
    final data = await request(
      'POST',
      '/media/upload-url',
      body: {
        'purpose': purpose,
        'content_type': contentType,
      },
    );

    final uploadUrl = data['upload_url'];

    if (uploadUrl is! String || uploadUrl.isEmpty) {
      throw const ApiException(
        'The server did not provide a media upload URL.',
      );
    }

    final bytes = await file.readAsBytes();

    final response = await _send(
      () => http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': contentType},
        body: bytes,
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ApiException(
        'Media upload failed. Please try again.',
      );
    }

    return data;
  }

  static Future<String> mediaUrl(String key) async {
    final cached = _mediaUrlCache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _mediaUrlCacheTtl) {
      return cached.url;
    }
    final data = await request(
      'GET',
      '/media/download-url?key=${Uri.encodeQueryComponent(key)}',
    );

    final url = data['url'];

    if (url is! String || url.isEmpty) {
      throw const ApiException(
        'The server did not provide a media URL.',
      );
    }

    _mediaUrlCache[key] = (url: url, fetchedAt: DateTime.now());
    return url;
  }

  static Future<String> blurredProfileUrl(int ownerId) async {
    final data = await request('GET', '/media/blurred-profile-url?owner_id=$ownerId');
    final url = data['url'];
    if (url is! String || url.isEmpty) throw const ApiException('Could not load the protected photo preview.');
    return url;
  }
  static Future<Map<String, dynamic>> requestPhotoReveal(int ownerId) =>
      request('POST', '/photos/$ownerId/reveal-request');
  static Future<List<dynamic>> photoRevealRequests() => list('/photos/reveal-requests');
  static Future<void> decidePhotoReveal(int requestId, String decision) async {
    await request('POST', '/photos/reveal-requests/$requestId/decision', body: {'decision': decision});
  }
  static Future<void> setMessageRetention(int messageId, dynamic seconds) async {
    await request('PATCH', '/messages/$messageId/retention', body: {'expires_in_seconds': seconds});
  }
  static Future<void> reactToMessage(int messageId, String reaction) async {
    await request('POST', '/messages/$messageId/reaction', body: {'reaction': reaction});
  }
  static Future<void> deleteMessageForMe(int messageId) async { await request('DELETE', '/messages/$messageId'); }
  static Future<void> clearConversationForMe(int conversationId) async { await request('DELETE', '/conversations/$conversationId/messages'); }
  static Future<void> markConversationRead(int conversationId) async { await request('POST', '/conversations/$conversationId/read'); }
  static Future<void> markAllConversationsRead() async { await request('POST', '/conversations/read-all'); }

  // Date safety kit
  static Future<Map<String, dynamic>> safetyContacts() => request('GET', '/safety/contacts');

  static Future<Map<String, dynamic>> addSafetyContact(String name, String email) =>
      request('POST', '/safety/contacts', body: {'name': name, 'email': email});

  static Future<void> deleteSafetyContact(int id) async {
    await request('DELETE', '/safety/contacts/$id');
  }

  static Future<Map<String, dynamic>> startCheckin({
    required String partnerName,
    required String place,
    required int minutes,
    required List<int> contactIds,
  }) =>
      request('POST', '/safety/checkins', body: {
        'partner_name': partnerName,
        'place': place,
        'minutes': minutes,
        'contact_ids': contactIds,
      });

  static Future<Map<String, dynamic>> activeCheckin() => request('GET', '/safety/checkins/active');

  static Future<void> checkinLocation(int id, double lat, double lng) async {
    await request('POST', '/safety/checkins/$id/location', body: {'latitude': lat, 'longitude': lng});
  }

  static Future<Map<String, dynamic>> extendCheckin(int id, int minutes) =>
      request('POST', '/safety/checkins/$id/extend', body: {'minutes': minutes});

  static Future<Map<String, dynamic>> safeCheckin(int id) => request('POST', '/safety/checkins/$id/safe');

  static Future<Map<String, dynamic>> sosCheckin(int id) => request('POST', '/safety/checkins/$id/sos');

  // Voice intro
  static Future<Map<String, dynamic>> voiceBio(int userId) => request('GET', '/users/$userId/voice-bio');

  static Future<void> setVoiceBio(String key, int seconds) async {
    await request('PUT', '/me/voice-bio', body: {'media_key': key, 'duration_seconds': seconds});
  }

  static Future<void> deleteVoiceBio() async {
    await request('DELETE', '/me/voice-bio');
  }

  // Blind voice dates
  static Future<Map<String, dynamic>> blindJoin() => request('POST', '/blind/join');

  static Future<Map<String, dynamic>> blindState() => request('GET', '/blind/state');

  static Future<void> blindLeaveQueue() async {
    await request('DELETE', '/blind/queue');
  }

  static Future<Map<String, dynamic>> blindSession(int id) => request('GET', '/blind/$id');

  static Future<Map<String, dynamic>> blindToken(int id) => request('POST', '/blind/$id/token');

  static Future<Map<String, dynamic>> blindChoice(int id, String choice) =>
      request('POST', '/blind/$id/choice', body: {'choice': choice});

  static Future<void> blindReport(int id, String reason) async {
    await request('POST', '/blind/$id/report', body: {'reason': reason});
  }

  // Identity verification

  static Future<Map<String, dynamic>> submitVerification(
    String livenessMediaKey,
    String comparisonPhotoKey,
  ) {
    return request(
      'POST',
      '/verification/submit',
      body: {
        'liveness_media_key': livenessMediaKey,
        'comparison_photo_key': comparisonPhotoKey,
      },
    );
  }

  static Future<Map<String, dynamic>> verificationStatus() {
    return request('GET', '/verification/status');
  }

  // Connections

  static Future<Map<String, dynamic>> connect(int userId) {
    return request('POST', '/connections/$userId');
  }

  static Future<List<dynamic>> connections() {
    return list('/connections');
  }

  static Future<Map<String, dynamic>> accept(int userId) {
    return request('POST', '/connections/$userId/accept');
  }

  // Conversations and messages

  static Future<List<dynamic>> conversations() {
    return list('/conversations');
  }

  static Future<Map<String, dynamic>> openConversation(int targetUserId) {
    return request('POST', '/conversations/open/$targetUserId');
  }

  static Future<List<dynamic>> messages(int conversationId) {
    return list('/conversations/$conversationId/messages');
  }

  static Future<Map<String, dynamic>> sendMessage(
    int targetId,
    String body, {
    int? expiresInSeconds,
    int? replyToMessageId,
  }) {
    return request(
      'POST',
      '/messages/$targetId',
      body: {'body': body, 'expires_in_seconds': expiresInSeconds, 'reply_to_message_id': replyToMessageId},
    );
  }

  // Safety

  static Future<void> block(int userId) async {
    await request('POST', '/block/$userId');
  }

  static Future<void> report(int userId, String reason) async {
    await request(
      'POST',
      '/report/$userId',
      body: {'reason': reason},
    );
  }


  // OS dating experience: privacy, compatibility and trust.
  static Future<Map<String, dynamic>> featurePreferences() =>
      request('GET', '/features/preferences');

  static Future<Map<String, dynamic>> updateFeaturePreferences(
    Map<String, dynamic> preferences,
  ) => request('PATCH', '/features/preferences', body: preferences);

  static Future<Map<String, dynamic>> featureTrustStatus() =>
      request('GET', '/features/trust');

  static Future<List<dynamic>> icebreakers({String category = 'naija'}) async {
    final result = await request(
      'GET',
      '/features/icebreakers?category=${Uri.encodeQueryComponent(category)}',
    );
    final items = result['items'];
    return items is List ? items : <dynamic>[];
  }

  // Administration

  static Future<List<dynamic>> adminVerifications() {
    return list('/admin/verifications');
  }

  static Future<Map<String, dynamic>> review(
    int verificationId,
    String decision,
    String note,
  ) {
    return request(
      'POST',
      '/admin/verifications/$verificationId/review',
      body: {'decision': decision, 'note': note},
    );
  }

  static Future<List<dynamic>> adminReports() {
    return list('/admin/reports');
  }

  static Future<Map<String, dynamic>> suspend(int userId) {
    return request('POST', '/admin/users/$userId/suspend');
  }
}