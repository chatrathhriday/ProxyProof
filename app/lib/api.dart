import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown for any non-2xx response; [message] is the server's `error` field.
class ApiException implements Exception {
  ApiException(this.status, this.message, [this.code]);
  final int status;
  final String message;
  final String? code; // machine-readable reason, e.g. BIO_REQUIRED
  @override
  String toString() => message;
}

/// JSON client: server URL, JWT, a cache for instant screens.
///
/// Speed notes:
/// - one persistent [http.Client], so the HTTPS connection (TLS handshake) is reused
///   instead of renegotiated on every 10 s report;
/// - GET responses are cached (memory + disk) so screens paint immediately with the last
///   known data and refresh in the background;
/// - generous timeout on the very first request, because a free-tier server may be waking up.
class Api {
  Api._();
  static final Api instance = Api._();

  // Release builds pass the deployed URL: flutter build apk --dart-define=API_URL=https://...
  // Dev default: `adb reverse tcp:3000 tcp:3000` tunnels the phone's localhost to the laptop.
  static const defaultBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  final _client = http.Client();
  final _memo = <String, dynamic>{};
  late SharedPreferences _prefs;
  String baseUrl = defaultBaseUrl;
  String? token;
  Map<String, dynamic>? user;
  bool _warm = false;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? defaultBaseUrl;
    token = _prefs.getString('token');
    final u = _prefs.getString('user');
    user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
    unawaited(_wake());
  }

  /// Fire-and-forget ping on launch so the server is awake before the user taps anything.
  Future<void> _wake() async {
    try {
      await _client.get(Uri.parse('$baseUrl/health')).timeout(const Duration(seconds: 60));
      _warm = true;
    } catch (_) {}
  }

  String get role => user?['role'] as String? ?? '';

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString('baseUrl', baseUrl);
  }

  Future<void> login(String email, String password) async =>
      _saveSession(await post('/auth/login', {'email': email, 'password': password}));

  /// Student sign-in: Google ID token -> our JWT (server enforces @vitstudent.ac.in).
  Future<void> googleLogin(String idToken) async => _saveSession(await post('/auth/google', {'idToken': idToken}));

  Future<void> _saveSession(dynamic res) async {
    token = res['token'] as String;
    user = res['user'] as Map<String, dynamic>;
    await _prefs.setString('token', token!);
    await _prefs.setString('user', jsonEncode(user));
  }

  Future<void> logout() async {
    token = null;
    user = null;
    _memo.clear();
    for (final k in _prefs.getKeys().where((k) => k.startsWith('cache:'))) {
      await _prefs.remove(k);
    }
    await _prefs.remove('token');
    await _prefs.remove('user');
  }

  /// Last successful response for [path], if any (instant first paint).
  dynamic cached(String path) {
    if (_memo.containsKey(path)) return _memo[path];
    final s = _prefs.getString('cache:$path');
    return s == null ? null : (_memo[path] = jsonDecode(s));
  }

  Future<dynamic> get(String path) async {
    final data = await _send('GET', path);
    _memo[path] = data;
    unawaited(_prefs.setString('cache:$path', jsonEncode(data)));
    return data;
  }

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))..headers['content-type'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final streamed = await _client.send(req).timeout(Duration(seconds: _warm ? 15 : 60));
    final res = await http.Response.fromStream(streamed);
    _warm = true;
    final data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final map = data is Map ? data : const {};
      throw ApiException(res.statusCode, map['error'] as String? ?? 'HTTP ${res.statusCode}', map['code'] as String?);
    }
    return data;
  }
}
