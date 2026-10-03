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
  List<BackupEntry>? _backups;
  List<FileEntry>? _files;
  List<SettingEntry>? _settings;
  bool _actionBusy = false;
  bool _backupActionBusy = false;
  bool _fileActionBusy = false;
  bool _settingsBusy = false;

  @override
  void initState() {
    super.initState();
    _client = context.read<AppModel>().client;
    _poll();
    _loadUsers();
    _loadBackups();
    _loadFiles();
    _loadSettings();
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

  Future<void> _loadBackups() async {
    try {
      final backups = await _client.getBackups(_id);
      if (mounted) setState(() => _backups = backups);
    } on AmpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadFiles() async {
    try {
      final files = await _client.getFiles(_id);
      if (mounted) setState(() => _files = files);
    } on AmpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _client.getSettings(_id);
      if (mounted) setState(() => _settings = settings);
    } on AmpException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _nextBackupName() {
    final stamp = DateTime.now().toUtc().toIso8601String();
    return 'backup-${stamp.replaceAll(RegExp(r'[:.TZ-]'), '')}';
  }

  Future<void> _createBackup() async {
    final controller = TextEditingController(text: _nextBackupName());
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup erstellen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Backup-Name',
            hintText: 'backup-20240603',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _backupActionBusy = true);
    try {
      await _client.createBackup(_id, name);
      await _loadBackups();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Backup „$name“ wird erstellt.')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _backupActionBusy = false);
    }
  }

  Future<void> _restoreBackup(BackupEntry backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup wiederherstellen?'),
        content: Text('„${backup.name}“ wirklich wiederherstellen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _backupActionBusy = true);
    try {
      await _client.restoreBackup(_id, backup.name);
      await _loadBackups();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Backup „${backup.name}“ wird wiederhergestellt.'),
          ),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _backupActionBusy = false);
    }
  }

  Future<void> _deleteBackup(BackupEntry backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup löschen?'),
        content: Text('„${backup.name}“ dauerhaft löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _backupActionBusy = true);
    try {
      await _client.deleteBackup(_id, backup.name);
      await _loadBackups();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Backup „${backup.name}“ wurde gelöscht.')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _backupActionBusy = false);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ordner erstellen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Pfad',
            hintText: 'z. B. config/addons',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Erstellen'),
          ),
        ],
      ),
    );
    if (path == null || path.trim().isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fileActionBusy = true);
    try {
      await _client.createDirectory(_id, path);
      await _loadFiles();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Ordner „$path“ wird erstellt.')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _fileActionBusy = false);
    }
  }

  Future<void> _deleteFile(FileEntry file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datei löschen?'),
        content: Text('„${file.path}“ dauerhaft löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fileActionBusy = true);
    try {
      await _client.deleteFile(_id, file.path);
      await _loadFiles();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Datei „${file.name}“ wurde gelöscht.')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _fileActionBusy = false);
    }
  }

  Future<void> _renameFile(FileEntry file) async {
    final controller = TextEditingController(text: file.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datei umbenennen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Neuer Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Umbenennen'),
          ),
        ],
      ),
    );
    if (newName == null || newName.trim().isEmpty || newName == file.name)
      return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fileActionBusy = true);
    try {
      await _client.renameFile(_id, file.path, newName);
      await _loadFiles();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('„${file.name}“ wird umbenannt.')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _fileActionBusy = false);
    }
  }

  Future<void> _editSetting(SettingEntry setting) async {
    final controller = TextEditingController(text: setting.value);
    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(setting.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Wert (${setting.type})',
            hintText: setting.description,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue == setting.value) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _settingsBusy = true);
    try {
      await _client.setSetting(_id, setting.name, newValue);
      await _loadSettings();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Setting „${setting.name}“ gespeichert.')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _settingsBusy = false);
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
      length: 6,
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
              Tab(icon: Icon(Icons.backup_outlined), text: 'Backups'),
              Tab(icon: Icon(Icons.folder_open), text: 'Dateien'),
              Tab(icon: Icon(Icons.tune), text: 'Settings'),
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
                  _BackupsTab(
                    backups: _backups,
                    onRefresh: _loadBackups,
                    busy: _backupActionBusy,
                    onCreate: _createBackup,
                    onRestore: _restoreBackup,
                    onDelete: _deleteBackup,
                  ),
                  _FilesTab(
                    files: _files,
                    onRefresh: _loadFiles,
                    busy: _fileActionBusy,
                    onCreateFolder: _createFolder,
                    onDelete: _deleteFile,
                    onRename: _renameFile,
                  ),
                  _SettingsTab(
                    settings: _settings,
                    busy: _settingsBusy,
                    onRefresh: _loadSettings,
                    onEdit: _editSetting,
                  ),
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

class _BackupsTab extends StatelessWidget {
  const _BackupsTab({
    required this.backups,
    required this.onRefresh,
    required this.onCreate,
    required this.onRestore,
    required this.onDelete,
    this.busy = false,
  });

  final List<BackupEntry>? backups;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreate;
  final Future<void> Function(BackupEntry) onRestore;
  final Future<void> Function(BackupEntry) onDelete;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final list = backups;
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      const Text('Keine Backups vorhanden.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy ? null : onCreate,
                        icon: const Icon(Icons.backup_outlined),
                        label: const Text('Backup erstellen'),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onCreate,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Backup erstellen'),
                  ),
                ),
                const SizedBox(height: 8),
                ...list.map(
                  (backup) => Card(
                    child: ListTile(
                      title: Text(backup.name),
                      subtitle: Text(
                        [
                          if (backup.createdAt != null &&
                              backup.createdAt!.isNotEmpty)
                            backup.createdAt!,
                          if (backup.sizeLabel.isNotEmpty) backup.sizeLabel,
                        ].join(' • '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Wiederherstellen',
                            icon: const Icon(Icons.restore),
                            onPressed: busy ? null : () => onRestore(backup),
                          ),
                          IconButton(
                            tooltip: 'Löschen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: busy ? null : () => onDelete(backup),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------

class _FilesTab extends StatelessWidget {
  const _FilesTab({
    required this.files,
    required this.onRefresh,
    required this.onCreateFolder,
    required this.onDelete,
    required this.onRename,
    this.busy = false,
  });

  final List<FileEntry>? files;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateFolder;
  final Future<void> Function(FileEntry) onDelete;
  final Future<void> Function(FileEntry) onRename;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final list = files;
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    children: [
                      const Text('Keine Dateien gefunden.'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: busy ? null : onCreateFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('Ordner erstellen'),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onCreateFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Ordner erstellen'),
                  ),
                ),
                const SizedBox(height: 8),
                ...list.map(
                  (file) => Card(
                    child: ListTile(
                      leading: Icon(
                        file.isDirectory
                            ? Icons.folder
                            : Icons.insert_drive_file,
                      ),
                      title: Text(file.name),
                      subtitle: Text(
                        [
                          file.path,
                          if (file.sizeLabel.isNotEmpty) file.sizeLabel,
                        ].join(' • '),
                      ),
                      trailing: file.isDirectory
                          ? null
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Umbenennen',
                                  icon: const Icon(
                                    Icons.drive_file_rename_outline,
                                  ),
                                  onPressed: busy ? null : () => onRename(file),
                                ),
                                IconButton(
                                  tooltip: 'Löschen',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: busy ? null : () => onDelete(file),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.settings,
    required this.onRefresh,
    required this.onEdit,
    this.busy = false,
  });

  final List<SettingEntry>? settings;
  final Future<void> Function() onRefresh;
  final Future<void> Function(SettingEntry) onEdit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final list = settings;
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Keine Settings gefunden.')),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                ...list.map(
                  (SettingEntry setting) => Card(
                    child: ListTile(
                      title: Text(setting.name),
                      subtitle: Text(
                        [
                          setting.type,
                          setting.value,
                          setting.description,
                        ].where((s) => s.isNotEmpty).join(' • '),
                      ),
                      trailing: IconButton(
                        tooltip: 'Bearbeiten',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: busy ? null : () => onEdit(setting),
                      ),
                      isThreeLine: setting.description.isNotEmpty,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
