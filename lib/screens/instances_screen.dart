import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/amp_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/state_badge.dart';
import 'instance_detail_screen.dart';
import 'settings_screen.dart';

class InstancesScreen extends StatefulWidget {
  const InstancesScreen({super.key});

  @override
  State<InstancesScreen> createState() => _InstancesScreenState();
}

class _InstancesScreenState extends State<InstancesScreen> {
  List<AmpInstance>? _instances;
  String? _error;
  Timer? _timer;
  AmpClient? _client;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload whenever the settings (and with them the client) change.
    final client = Provider.of<AppModel>(context).clientOrNull;
    if (!identical(client, _client)) {
      _client = client;
      _instances = null;
      _error = null;
      _timer?.cancel();
      if (client == null) return;
      _load();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    try {
      final list = await client.getInstances();
      if (!mounted || !identical(client, _client)) return;
      setState(() {
        _instances = list;
        _error = null;
      });
    } on AmpException catch (e) {
      if (!mounted || !identical(client, _client)) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _open(AmpInstance i) async {
    if (!i.running) {
      final start = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(i.displayName),
          content: const Text(
            'Die AMP-Instanz ist nicht gestartet. Jetzt starten?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Starten'),
            ),
          ],
        ),
      );
      if (start != true || !mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await _client!.startInstanceProcess(i);
        messenger.showSnackBar(
          const SnackBar(content: Text('Instanz wird gestartet …')),
        );
      } on AmpException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      await _load();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InstanceDetailScreen(instance: i)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Instanzen'),
        actions: [
          IconButton(
            tooltip: 'Einstellungen',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final instances = _instances;
    if (instances == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (instances == null) {
      return _Message(
        icon: Icons.cloud_off,
        text: _error!,
        action: FilledButton(
          onPressed: _load,
          child: const Text('Erneut versuchen'),
        ),
      );
    }
    if (instances.isEmpty) {
      return const _Message(
        icon: Icons.inbox_outlined,
        text: 'Keine Instanzen gefunden.',
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: [
        if (_error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.warning_amber),
              title: Text(_error!),
            ),
          ),
        for (final i in instances) _InstanceTile(i, onTap: () => _open(i)),
      ],
    );
  }
}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile(this.instance, {required this.onTap});

  final AmpInstance instance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = instance;
    final metrics = i.running ? i.metrics.values.toList() : <Metric>[];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.displayName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          i.subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  i.running
                      ? StateBadge(i.appState)
                      : const StateBadge.offline(),
                ],
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    for (final m in metrics)
                      Text(
                        '${m.label}: ${m.valueText}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Scrollable so that pull-to-refresh works on empty/error states.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 16),
          Center(child: action),
        ],
      ],
    );
  }
}
