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

/// Thin JSON client. Holds the server URL and the JWT.
class Api {
  Api._();
  static final Api instance = Api._();

  // Release builds pass the deployed URL: flutter build apk --dart-define=API_URL=https://...
  // Dev default: `adb reverse tcp:3000 tcp:3000` tunnels the phone's localhost to the laptop.
  // Always changeable on the login screen ("Server").
  static const defaultBaseUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  late SharedPreferences _prefs;
  String baseUrl = defaultBaseUrl;
  String? token;
  Map<String, dynamic>? user;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? defaultBaseUrl;
    token = _prefs.getString('token');
    final u = _prefs.getString('user');
    user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
  }

  String get role => user?['role'] as String? ?? '';

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _prefs.setString('baseUrl', baseUrl);
  }

  Future<void> login(String email, String password, {String? name}) async {
    final res = name == null
        ? await post('/auth/login', {'email': email, 'password': password})
        : await post('/auth/register', {'email': email, 'password': password, 'name': name});
    token = res['token'] as String;
    user = res['user'] as Map<String, dynamic>;
    await _prefs.setString('token', token!);
    await _prefs.setString('user', jsonEncode(user));
  }

  Future<void> logout() async {
    token = null;
    user = null;
    await _prefs.remove('token');
    await _prefs.remove('user');
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body);

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'))..headers['content-type'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send().timeout(const Duration(seconds: 10));
    final res = await http.Response.fromStream(streamed);
    final data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final map = data is Map ? data : const {};
      throw ApiException(res.statusCode, map['error'] as String? ?? 'HTTP ${res.statusCode}', map['code'] as String?);
    }
    return data;
  }
}
