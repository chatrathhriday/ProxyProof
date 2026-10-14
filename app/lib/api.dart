import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown for any non-2xx response; [message] is the server's `error` field.
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Thin JSON client. Holds the server URL, the JWT and this install's device id.
class Api {
  Api._();
  static final Api instance = Api._();

  // Dev default: `adb reverse tcp:3000 tcp:3000` tunnels the phone's localhost to the
  // laptop over USB (works even on campus Wi-Fi that isolates clients).
  // Changeable on the login screen; release builds will point at the Render URL.
  static const defaultBaseUrl = 'http://localhost:3000';

  late SharedPreferences _prefs;
  String baseUrl = defaultBaseUrl;
  String? token;
  Map<String, dynamic>? user;
  late String deviceUid;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    baseUrl = _prefs.getString('baseUrl') ?? defaultBaseUrl;
    token = _prefs.getString('token');
    final u = _prefs.getString('user');
    user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
    // Random per-install id. Phase 3 replaces "trust this id" with a Keystore-backed key.
    deviceUid = _prefs.getString('deviceUid') ?? _randomHex(16);
    await _prefs.setString('deviceUid', deviceUid);
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
    final req = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['content-type'] = 'application/json';
    if (token != null) req.headers['authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send().timeout(const Duration(seconds: 10));
    final res = await http.Response.fromStream(streamed);
    final data = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (data is Map ? data['error'] : null) ?? 'HTTP ${res.statusCode}');
    }
    return data;
  }

  static String _randomHex(int bytes) {
    final r = Random.secure();
    return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
