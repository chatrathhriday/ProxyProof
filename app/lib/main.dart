import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';
import 'screens/admin_home.dart';
import 'screens/device_gate.dart';
import 'screens/login_screen.dart';
import 'screens/organiser_home.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw edge-to-edge under transparent system bars: modern look, no colour seams.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
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
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
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
      'organiser' => const OrganiserHome(),
      'admin' => const AdminHome(),
      _ => const DeviceGate(), // students always pass the device check first
    };
  }
}

/// Logs out and returns to the login screen. Used by every home screen.
Future<void> logout(BuildContext context) async {
  await Api.instance.logout();
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {} // not initialised (staff/demo login)
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
}
