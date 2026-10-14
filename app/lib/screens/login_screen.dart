import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _server = TextEditingController(text: Api.instance.baseUrl);
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.setBaseUrl(_server.text);
      await Api.instance.login(_email.text.trim(), _password.text, name: _register ? _name.text.trim() : null);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeRouter()));
    } catch (e) {
      setState(() => _error = e is ApiException ? e.message : 'Cannot reach server: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.bluetooth_searching, size: 56),
                const SizedBox(height: 8),
                Text('ProxyProof', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 32),
                if (_register) ...[
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Full name'),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Please wait…' : (_register ? 'Create student account' : 'Log in')),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register ? 'Have an account? Log in' : 'New student? Register'),
                ),
                ExpansionTile(
                  title: const Text('Server'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    TextField(
                      controller: _server,
                      decoration: const InputDecoration(labelText: 'API URL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
