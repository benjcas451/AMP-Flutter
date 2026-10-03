import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/amp_client.dart';
import '../api/models.dart';
import '../services/instance_action_controller.dart';
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
  final InstanceActionController _actionState = InstanceActionController();
  int _loadVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload whenever the settings (and with them the client) change.
    final client = Provider.of<AppModel>(context).clientOrNull;
    if (!identical(client, _client)) {
      _client = client;
      _instances = null;
      _error = null;
      _actionState.clearAll();
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
    final version = ++_loadVersion;
    try {
      final list = await client.getInstances();
      if (!mounted || !identical(client, _client) || version != _loadVersion) {
        return;
      }
      setState(() {
        _instances = list;
        _error = null;
      });
    } on AmpException catch (e) {
      if (!mounted || !identical(client, _client) || version != _loadVersion) {
        return;
      }
      setState(() => _error = e.message);
    }
  }

  Future<void> _open(AmpInstance i) async {
    if (_actionState.isLocked(i.id)) {
      return;
    }
    if (!i.running) {
      await _setInstanceRunning(i, running: true, confirmStart: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => InstanceDetailScreen(instance: i)),
    );
    if (mounted) _load();
  }

  Future<void> _setInstanceRunning(
    AmpInstance i, {
    required bool running,
    bool confirmStart = false,
  }) async {
    final client = _client;
    if (client == null || _actionState.isLocked(i.id)) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!running || confirmStart) {
        _actionState.beginConfirmation(i.id);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(running ? 'Instanz starten?' : 'Instanz stoppen?'),
            content: Text(
              running
                  ? '${i.displayName}: Die AMP-Instanz ist nicht gestartet. Jetzt starten?'
                  : '${i.displayName}: Die gesamte AMP-Instanz wird gestoppt. '
                        'Ein laufender Server wird dabei ebenfalls beendet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(running ? 'Instanz starten' : 'Instanz stoppen'),
              ),
            ],
          ),
        );
        if (confirmed != true) {
          _actionState.clearConfirmation(i.id);
          return;
        }
      }
      if (!mounted || !identical(client, _client)) return;
      _actionState.beginBusy(i.id, running: running);
      if (running) {
        await client.startInstanceProcess(i);
      } else {
        await client.stopInstanceProcess(i);
      }
      if (!mounted || !identical(client, _client)) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            running ? 'Instanz wird gestartet …' : 'Instanz wird gestoppt …',
          ),
        ),
      );
      // Keep controls disabled until ADS reports the actual process state.
      for (var attempt = 0; attempt <= 15; attempt++) {
        await _load();
        if (!mounted || !identical(client, _client)) return;
        if (_instances?.any(
              (item) => item.id == i.id && item.running == running,
            ) ==
            true) {
          return;
        }
        if (attempt == 15) break;
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || !identical(client, _client)) return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Der Statuswechsel wurde noch nicht bestätigt. '
            'Bitte die Instanzliste aktualisieren.',
          ),
        ),
      );
    } on AmpException catch (e) {
      if (mounted && identical(client, _client)) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && identical(client, _client)) {
        _actionState.finish(i.id);
      }
    }
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
        for (final i in instances)
          _InstanceTile(
            i,
            starting: _actionState.isBusy(i.id)
                ? _actionState.isPendingStart(i.id)
                : null,
            onTap: () => _open(i),
            onToggle: () => _setInstanceRunning(i, running: !i.running),
          ),
      ],
    );
  }
}

class _InstanceTile extends StatelessWidget {
  const _InstanceTile(
    this.instance, {
    required this.starting,
    required this.onTap,
    required this.onToggle,
  });

  final AmpInstance instance;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final bool? starting;

  @override
  Widget build(BuildContext context) {
    final i = instance;
    final metrics = i.running ? i.metrics.values.toList() : <Metric>[];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: starting == null ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    starting != null
                        ? (starting! ? 'Instanz startet …' : 'Instanz stoppt …')
                        : 'AMP-Instanz: ${i.running ? 'Läuft' : 'Gestoppt'}',
                  ),
                  if (i.running)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Server: '),
                        StateBadge(i.appState),
                      ],
                    ),
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: starting == null ? onToggle : null,
                    icon: starting != null
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(i.running ? Icons.stop : Icons.play_arrow),
                    label: Text(
                      i.running ? 'Instanz stoppen' : 'Instanz starten',
                    ),
                  ),
                  if (i.running)
                    TextButton.icon(
                      onPressed: starting == null ? onTap : null,
                      icon: const Icon(Icons.chevron_right),
                      label: const Text('Server verwalten'),
                    ),
                ],
              ),
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
