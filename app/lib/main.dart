import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/login_screen.dart';
import 'screens/organiser_home.dart';
import 'screens/student_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.instance.load();
  runApp(const ProxyProofApp());
}

class ProxyProofApp extends StatelessWidget {
  const ProxyProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxyProof',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3355FF), useMaterial3: true),
      home: const HomeRouter(),
    );
  }
}

/// Picks the first screen from the saved login + role.
class HomeRouter extends StatelessWidget {
  const HomeRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final api = Api.instance;
    if (api.token == null) return const LoginScreen();
    return switch (api.role) {
      'organiser' || 'admin' => const OrganiserHome(),
      _ => const StudentHome(),
    };
  }
}

/// Logs out and returns to the login screen. Used by every home screen's app bar.
Future<void> logout(BuildContext context) async {
  await Api.instance.logout();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (_) => false,
  );
}
