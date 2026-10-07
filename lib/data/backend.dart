import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';

/// Server settings, passed at build time:
///   flutter build ipa --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///                     --dart-define=SUPABASE_ANON_KEY=...
/// Without them the app runs fully offline on the bundled content.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}

class BackendException implements Exception {
  const BackendException(this.message, {this.offline = false});

  final String message;

  /// True when the request failed for lack of a connection.
  final bool offline;

  @override
  String toString() => message;
}

class TutorMessage {
  const TutorMessage({required this.fromStudent, required this.text});

  final bool fromStudent;
  final String text;

  Map<String, Object?> toJson() => {'role': fromStudent ? 'user' : 'assistant', 'content': text};
}

class TutorRequest {
  const TutorRequest({
    required this.gradeName,
    required this.studentName,
    required this.history,
    required this.question,
    required this.context,
    this.subjectName,
  });

  final String gradeName;
  final String studentName;
  final String? subjectName;
  final List<TutorMessage> history;
  final String question;

  /// Curriculum passages retrieved on the device (RAG): the tutor must answer
  /// from these.
  final List<({String title, String text})> context;

  Map<String, Object?> toJson() => {
    'grade': gradeName,
    'student': studentName,
    'subject': subjectName,
    'history': [for (final m in history) m.toJson()],
    'question': question,
    'context': [
      for (final c in context) {'title': c.title, 'text': c.text},
    ],
  };
}

/// Everything that needs the network. Each call may throw [BackendException].
abstract interface class Backend {
  bool get enabled;

  /// Grade id → latest pack version on the server.
  Future<Map<String, int>> packVersions();

  /// Raw pack JSON.
  Future<String> downloadPack(String gradeId);

  Future<String> askTutor(TutorRequest request);

  Future<void> uploadAttempts(String gradeId, List<AttemptRecord> attempts);
}

/// Used when no server is configured.
class OfflineBackend implements Backend {
  const OfflineBackend();

  static const _off = BackendException('لم يتم ربط التطبيق بالخادم بعد.');

  @override
  bool get enabled => false;

  @override
  Future<Map<String, int>> packVersions() => Future.error(_off);

  @override
  Future<String> downloadPack(String gradeId) => Future.error(_off);

  @override
  Future<String> askTutor(TutorRequest request) => Future.error(_off);

  @override
  Future<void> uploadAttempts(String gradeId, List<AttemptRecord> attempts) => Future.error(_off);
}

/// Supabase: content and the AI tutor via Edge Functions, progress via the
/// REST API under an anonymous auth session (no personal data is needed to
/// start; accounts for parents/teachers come in a later phase).
class SupabaseBackend implements Backend {
  SupabaseBackend({
    required this.url,
    required this.anonKey,
    required this._prefs,
    http.Client? client,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final String url;
  final String anonKey;
  final SharedPreferencesWithCache _prefs;
  final http.Client _client;
  final DateTime Function() _clock;

  static const _timeout = Duration(seconds: 20);
  static const _kAccess = 'auth.access';
  static const _kRefresh = 'auth.refresh';
  static const _kExpiry = 'auth.expiry';

  @override
  bool get enabled => true;

  @override
  Future<Map<String, int>> packVersions() async {
    final body = await _send('GET', '/functions/v1/content/manifest');
    final packs = (jsonDecode(body) as Map<String, dynamic>)['packs'] as Map<String, dynamic>;
    return packs.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  @override
  Future<String> downloadPack(String gradeId) => _send('GET', '/functions/v1/content/packs/$gradeId');

  @override
  Future<String> askTutor(TutorRequest request) async {
    final body = await _send('POST', '/functions/v1/ai-tutor', body: request.toJson(), auth: true);
    return (jsonDecode(body) as Map<String, dynamic>)['reply'] as String;
  }

  @override
  Future<void> uploadAttempts(String gradeId, List<AttemptRecord> attempts) async {
    if (attempts.isEmpty) return;
    await _send(
      'POST',
      '/rest/v1/attempts?on_conflict=uid',
      body: [
        for (final a in attempts) {...a.toJson(), 'grade_id': gradeId},
      ],
      auth: true,
      headers: {'Prefer': 'resolution=ignore-duplicates,return=minimal'},
    );
  }

  Future<String> _send(
    String method,
    String path, {
    Object? body,
    bool auth = false,
    Map<String, String> headers = const {},
  }) async {
    final token = auth ? await _accessToken() : anonKey;
    final request = http.Request(method, Uri.parse('$url$path'))
      ..headers.addAll({
        'apikey': anonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        ...headers,
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
      if (response.statusCode >= 400) {
        throw BackendException(_errorMessage(response));
      }
      return utf8.decode(response.bodyBytes);
    } on BackendException {
      rethrow;
    } on Exception {
      throw const BackendException('لا يوجد اتصال بالإنترنت.', offline: true);
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final msg = json['error'] ?? json['message'] ?? json['msg'];
      if (msg is String && msg.isNotEmpty) return msg;
    } on FormatException {
      // fall through
    }
    return 'حدث خطأ في الخادم (${response.statusCode}).';
  }

  /// Anonymous session, created on first use and refreshed when it expires.
  Future<String> _accessToken() async {
    final access = _prefs.getString(_kAccess);
    final expiry = _prefs.getInt(_kExpiry) ?? 0;
    if (access != null && _clock().millisecondsSinceEpoch < expiry - 60000) return access;
    final refresh = _prefs.getString(_kRefresh);
    String? body;
    if (refresh != null) {
      try {
        body = await _send('POST', '/auth/v1/token?grant_type=refresh_token', body: {'refresh_token': refresh});
      } on BackendException catch (e) {
        if (e.offline) rethrow;
        // Revoked or expired refresh token: start a new anonymous session.
      }
    }
    body ??= await _send('POST', '/auth/v1/signup', body: {'data': <String, Object>{}});
    final json = jsonDecode(body) as Map<String, dynamic>;
    final token = json['access_token'] as String;
    await _prefs.setString(_kAccess, token);
    await _prefs.setString(_kRefresh, json['refresh_token'] as String);
    await _prefs.setInt(
      _kExpiry,
      _clock().add(Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 3600)).millisecondsSinceEpoch,
    );
    return token;
  }
}
