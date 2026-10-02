import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/amp_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/state_badge.dart';

class InstanceDetailScreen extends StatefulWidget {
  const InstanceDetailScreen({super.key, required this.instance});

  final AmpInstance instance;

  @override
  State<InstanceDetailScreen> createState() => _InstanceDetailScreenState();
}

class _InstanceDetailScreenState extends State<InstanceDetailScreen> {
  static const _maxConsoleLines = 500;

  late final AmpClient _client;
  late final String _id = widget.instance.id;
  Timer? _timer;
  bool _polling = false;

  InstanceStatus? _status;
  String? _error;
  final List<ConsoleEntry> _console = [];
  List<String>? _users;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _client = context.read<AppModel>().client;
    _poll();
    _loadUsers();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final u = await _client.getUpdates(_id);
      if (!mounted) return;
      setState(() {
        if (u.status != null) _status = u.status;
        _console.addAll(u.console);
        if (_console.length > _maxConsoleLines) {
          _console.removeRange(0, _console.length - _maxConsoleLines);
        }
        _error = null;
      });
    } on AmpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _client.getUsers(_id);
      if (mounted) setState(() => _users = users);
    } on AmpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _run(
    String label,
    Future<void> Function() action, {
    bool confirm = false,
  }) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('$label?'),
          content: Text(
            '${widget.instance.displayName}: Aktion „$label“ wirklich ausführen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(label),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _actionBusy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text('$label gesendet.')));
    } on AmpException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
      _poll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.instance.displayName),
          actions: [
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: StateBadge(_status!.state)),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Übersicht'),
              Tab(icon: Icon(Icons.terminal), text: 'Konsole'),
              Tab(icon: Icon(Icons.people_outline), text: 'Spieler'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                leading: const Icon(Icons.warning_amber),
                actions: [
                  TextButton(onPressed: _poll, child: const Text('Erneut')),
                ],
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _OverviewTab(
                    status: _status,
                    busy: _actionBusy,
                    onStart: () =>
                        _run('Starten', () => _client.startServer(_id)),
                    onStop: () => _run(
                      'Stoppen',
                      () => _client.stopServer(_id),
                      confirm: true,
                    ),
                    onRestart: () => _run(
                      'Neustarten',
                      () => _client.restartServer(_id),
                      confirm: true,
                    ),
                    onKill: () => _run(
                      'Beenden erzwingen',
                      () => _client.killServer(_id),
                      confirm: true,
                    ),
                  ),
                  _ConsoleTab(
                    entries: _console,
                    onSend: (msg) async {
                      await _client.sendConsole(_id, msg);
                      _poll();
                    },
                  ),
                  _UsersTab(users: _users, onRefresh: _loadUsers),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.status,
    required this.busy,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onKill,
  });

  final InstanceStatus? status;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onKill;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final state = s.state;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.circle, color: state.color),
            title: Text(state.label),
            subtitle: s.uptime.isNotEmpty && state.isRunning
                ? Text('Laufzeit: ${s.uptime}')
                : null,
          ),
        ),
        const SizedBox(height: 8),
        for (final m in s.metrics.values)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(m.label, style: theme.textTheme.titleSmall),
                      ),
                      Text(m.valueText),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: m.fraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy || !state.isStopped ? null : onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Starten'),
            ),
            FilledButton.tonalIcon(
              onPressed: busy || state.isStopped ? null : onStop,
              icon: const Icon(Icons.stop),
              label: const Text('Stoppen'),
            ),
            FilledButton.tonalIcon(
              onPressed: busy || !state.isRunning ? null : onRestart,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Neustarten'),
            ),
            OutlinedButton.icon(
              onPressed: busy || state.isStopped ? null : onKill,
              icon: const Icon(Icons.dangerous_outlined),
              label: const Text('Kill'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _ConsoleTab extends StatefulWidget {
  const _ConsoleTab({required this.entries, required this.onSend});

  final List<ConsoleEntry> entries;
  final Future<void> Function(String) onSend;

  @override
  State<_ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<_ConsoleTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final msg = _input.text.trim();
    if (msg.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(msg);
      _input.clear();
    } on AmpException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(DateTime? t) {
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)} ';
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final mono = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace', color: Colors.white);
    return Column(
      children: [
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'Noch keine Ausgabe.',
                      style: mono?.copyWith(color: Colors.white54),
                    ),
                  )
                // Reversed list keeps the view pinned to the newest line.
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: entries.length,
                    itemBuilder: (_, idx) {
                      final e = entries[entries.length - 1 - idx];
                      return SelectableText.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _time(e.timestamp),
                              style: mono?.copyWith(color: Colors.white38),
                            ),
                            if (e.source.isNotEmpty)
                              TextSpan(
                                text: '[${e.source}] ',
                                style: mono?.copyWith(
                                  color: Colors.lightBlueAccent,
                                ),
                              ),
                            TextSpan(
                              text: e.contents,
                              style: e.type.toLowerCase().contains('error')
                                  ? mono?.copyWith(color: Colors.redAccent)
                                  : mono,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    autocorrect: false,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Befehl eingeben …',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _UsersTab extends StatelessWidget {
  const _UsersTab({required this.users, required this.onRefresh});

  final List<String>? users;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = users;
    if (list == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Niemand online.')),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                leading: CircleAvatar(
                  child: Text(list[i].isEmpty ? '?' : list[i].characters.first),
                ),
                title: Text(list[i]),
              ),
            ),
    );
  }
}
