import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';

/// Admin's only job in the app: approve or reject device-change requests.
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  late Future<List> _pending = _load();

  Future<List> _load() async => await Api.instance.get('/devices/pending') as List;

  Future<void> _decide(Map d, bool approve) async {
    try {
      await Api.instance.post('/devices/${d['id']}/${approve ? 'approve' : 'reject'}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    setState(() => _pending = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device approvals'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => logout(context))],
      ),
      body: FutureBuilder(
        future: _pending,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _pending = _load()),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No pending requests 🎉')),
                  ),
                for (final d in list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${d['name']}', style: Theme.of(context).textTheme.titleMedium),
                          Text('${d['email']}'),
                          const SizedBox(height: 8),
                          Text('New phone: ${d['model']}'),
                          Text('Current phone: ${d['current_model'] ?? 'none'}'),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(onPressed: () => _decide(d as Map, false), child: const Text('Reject')),
                              const SizedBox(width: 8),
                              FilledButton(onPressed: () => _decide(d as Map, true), child: const Text('Approve')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
