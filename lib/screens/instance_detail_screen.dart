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
  List<SchedulerTask>? _tasks;
  List<AmpEvent>? _events;
  InstanceStatus? _updateStatus;
  bool _actionBusy = false;
  bool _backupActionBusy = false;
  bool _fileActionBusy = false;
  bool _settingsBusy = false;
  bool _tasksBusy = false;
  bool _updateBusy = false;

  final Map<String, String> _tabErrors = {};
  final Map<String, bool> _tabLoading = {};

  static const _tabConfig = {
    'backups': _TabSpec(
      module: 'LocalFileBackupPlugin',
      method: 'GetBackups',
      icon: Icon(Icons.backup_outlined),
      label: 'Backups',
    ),
    'files': _TabSpec(
      module: 'FileManagerPlugin',
      method: 'GetDirectoryListing',
      icon: Icon(Icons.folder_open),
      label: 'Dateien',
    ),
    'settings': _TabSpec(
      method: 'GetSettingsSpec',
      icon: Icon(Icons.tune),
      label: 'Settings',
    ),
    'tasks': _TabSpec(
      method: 'GetScheduleData',
      icon: Icon(Icons.schedule),
      label: 'Zeitplan',
    ),
    'events': _TabSpec(
      method: 'GetAuditLogEntries',
      icon: Icon(Icons.notifications_outlined),
      label: 'Ereignisse',
    ),
    'updates': _TabSpec(
      method: 'GetStatus',
      icon: Icon(Icons.system_update_alt),
      label: 'Updates',
    ),
  };

  bool _isTabSupported(String tab) {
    final spec = _tabConfig[tab];
    if (spec == null) return true;
    if (tab == 'updates' &&
        !_client.isMethodSupported('UpdateApplication', instanceId: _id)) {
      return false;
    }
    return _client.isMethodSupported(
      spec.method,
      module: spec.module,
      instanceId: _id,
    );
  }

  @override
  void initState() {
    super.initState();
    _client = context.read<AppModel>().client;
    _poll();
    _loadUsers();
    if (_isTabSupported('backups')) _loadBackups();
    if (_isTabSupported('files')) _loadFiles();
    if (_isTabSupported('settings')) _loadSettings();
    if (_isTabSupported('tasks')) _loadTasks();
    if (_isTabSupported('events')) _loadEvents();
    if (_isTabSupported('updates')) _loadUpdateStatus();
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
        if (u.status != null) {
          _status = u.status;
          _updateStatus = u.status;
        }
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

  Future<T?> _tryLoad<T>(
    String tab,
    Future<T> Function() fetch,
    void Function(T value) assign,
  ) async {
    if (!mounted) return null;
    if (_tabLoading[tab] == true) return null;
    setState(() {
      _tabLoading[tab] = true;
      _tabErrors.remove(tab);
    });
    try {
      final result = await fetch();
      if (mounted) {
        setState(() {
          assign(result);
          _tabLoading[tab] = false;
        });
      }
      return result;
    } on AmpException catch (e) {
      if (mounted) {
        setState(() {
          _tabErrors[tab] = e.message;
          _tabLoading[tab] = false;
        });
      }
      return null;
    } catch (e) {
      if (mounted) {
        setState(() {
          _tabErrors[tab] = 'Unerwarteter Fehler: $e';
          _tabLoading[tab] = false;
        });
      }
      return null;
    }
  }

  Future<void> _loadUsers() => _tryLoad<List<String>>(
    'users',
    () => _client.getUsers(_id),
    (List<String> v) {
      _users = v;
    },
  );

  Future<void> _loadBackups() => _tryLoad<List<BackupEntry>>(
    'backups',
    () => _client.getBackups(_id),
    (List<BackupEntry> v) {
      _backups = v;
    },
  );

  Future<void> _loadFiles() => _tryLoad<List<FileEntry>>(
    'files',
    () => _client.getFiles(_id),
    (List<FileEntry> v) {
      _files = v;
    },
  );

  Future<void> _loadSettings() => _tryLoad<List<SettingEntry>>(
    'settings',
    () => _client.getSettings(_id),
    (List<SettingEntry> v) {
      _settings = v;
    },
  );

  Future<void> _loadTasks() => _tryLoad<List<SchedulerTask>>(
    'tasks',
    () => _client.getTasks(_id),
    (List<SchedulerTask> v) {
      _tasks = v;
    },
  );

  Future<void> _loadEvents() => _tryLoad<List<AmpEvent>>(
    'events',
    () => _client.getEvents(_id),
    (List<AmpEvent> v) {
      _events = v;
    },
  );

  Future<void> _loadUpdateStatus() => _tryLoad<InstanceStatus>(
    'updates',
    () => _client.getUpdateStatus(_id),
    (InstanceStatus v) {
      _updateStatus = v;
    },
  );

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

    if (!mounted) return;
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

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _backupActionBusy = true);
    try {
      await _client.restoreBackup(_id, backup.id);
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

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _backupActionBusy = true);
    try {
      await _client.deleteBackup(_id, backup.id);
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

    if (!mounted) return;
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
        title: const Text('In den Papierkorb verschieben?'),
        content: Text('„${file.path}“ in den Papierkorb verschieben?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verschieben'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fileActionBusy = true);
    try {
      await _client.deleteFile(_id, file.path, isDirectory: file.isDirectory);
      await _loadFiles();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('„${file.name}“ wurde in den Papierkorb verschoben.'),
          ),
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
    if (newName == null || newName.trim().isEmpty || newName == file.name) {
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _fileActionBusy = true);
    try {
      await _client.renameFile(
        _id,
        file.path,
        newName,
        isDirectory: file.isDirectory,
      );
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
        title: Text(setting.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (setting.description.isNotEmpty) ...[
              Text(setting.description),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: setting.type.isEmpty
                    ? 'Wert'
                    : 'Wert (${setting.type})',
                helperText:
                    setting.key.isNotEmpty && setting.key != setting.displayName
                    ? setting.key
                    : null,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (newValue == null || newValue == setting.value) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _settingsBusy = true);
    try {
      await _client.setSetting(_id, setting.node, newValue);
      await _loadSettings();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Setting „${setting.displayName}“ gespeichert.'),
          ),
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

  Future<void> _toggleTask(SchedulerTask task) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _tasksBusy = true);
    try {
      await _client.setTaskEnabled(_id, task.id, !task.enabled);
      await _loadTasks();
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Task „${task.name}“ ${task.enabled ? 'deaktiviert' : 'aktiviert'}.',
            ),
          ),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _tasksBusy = false);
    }
  }

  Future<void> _runUpdate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spielserver aktualisieren?'),
        content: const Text(
          'AMP aktualisiert die Spielserver-Dateien aus der konfigurierten Quelle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update starten'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _updateBusy = true);
    try {
      await _client.runUpdate(_id);
      await _loadUpdateStatus();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Update wird ausgeführt …')),
        );
      }
    } on AmpException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _updateBusy = false);
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
    // Build visible tabs based on which AMP API methods are supported
    final allTabs = <_TabEntry>[
      _TabEntry(
        id: 'overview',
        spec: const _TabSpec(
          method: '',
          icon: Icon(Icons.dashboard_outlined),
          label: 'Übersicht',
        ),
        body: _OverviewTab(
          status: _status,
          busy: _actionBusy,
          onStart: () => _run('Starten', () => _client.startServer(_id)),
          onStop: () =>
              _run('Stoppen', () => _client.stopServer(_id), confirm: true),
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
      ),
      _TabEntry(
        id: 'console',
        spec: const _TabSpec(
          method: '',
          icon: Icon(Icons.terminal),
          label: 'Konsole',
        ),
        body: _ConsoleTab(
          entries: _console,
          onSend: (msg) async {
            await _client.sendConsole(_id, msg);
            _poll();
          },
        ),
      ),
      _TabEntry(
        id: 'users',
        spec: const _TabSpec(
          method: '',
          icon: Icon(Icons.people_outline),
          label: 'Spieler',
        ),
        body: _UsersTab(
          users: _users,
          onRefresh: _loadUsers,
          error: _tabErrors['users'],
        ),
      ),
      if (_isTabSupported('backups'))
        _TabEntry(
          id: 'backups',
          spec: _tabConfig['backups']!,
          body: _BackupsTab(
            backups: _backups,
            onRefresh: _loadBackups,
            busy: _backupActionBusy,
            onCreate: _createBackup,
            onRestore: _restoreBackup,
            onDelete: _deleteBackup,
            loading: _tabLoading['backups'] ?? false,
            error: _tabErrors['backups'],
          ),
        ),
      if (_isTabSupported('files'))
        _TabEntry(
          id: 'files',
          spec: _tabConfig['files']!,
          body: _FilesTab(
            files: _files,
            onRefresh: _loadFiles,
            busy: _fileActionBusy,
            onCreateFolder: _createFolder,
            onDelete: _deleteFile,
            onRename: _renameFile,
            loading: _tabLoading['files'] ?? false,
            error: _tabErrors['files'],
          ),
        ),
      if (_isTabSupported('settings'))
        _TabEntry(
          id: 'settings',
          spec: _tabConfig['settings']!,
          body: _SettingsTab(
            settings: _settings,
            busy: _settingsBusy,
            onRefresh: _loadSettings,
            onEdit: _editSetting,
            loading: _tabLoading['settings'] ?? false,
            error: _tabErrors['settings'],
          ),
        ),
      if (_isTabSupported('tasks'))
        _TabEntry(
          id: 'tasks',
          spec: _tabConfig['tasks']!,
          body: _TasksTab(
            tasks: _tasks,
            busy: _tasksBusy,
            onRefresh: _loadTasks,
            onToggle: _toggleTask,
            loading: _tabLoading['tasks'] ?? false,
            error: _tabErrors['tasks'],
          ),
        ),
      if (_isTabSupported('events'))
        _TabEntry(
          id: 'events',
          spec: _tabConfig['events']!,
          body: _EventsTab(
            events: _events,
            onRefresh: _loadEvents,
            loading: _tabLoading['events'] ?? false,
            error: _tabErrors['events'],
          ),
        ),
      if (_isTabSupported('updates'))
        _TabEntry(
          id: 'updates',
          spec: _tabConfig['updates']!,
          body: _UpdatesTab(
            status: _updateStatus,
            busy: _updateBusy,
            onRefresh: _loadUpdateStatus,
            onRunUpdate: _runUpdate,
            loading: _tabLoading['updates'] ?? false,
            error: _tabErrors['updates'],
          ),
        ),
    ];

    return DefaultTabController(
      length: allTabs.length,
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
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: allTabs
                .map((t) => Tab(icon: t.spec.icon, text: t.spec.label))
                .toList(),
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
              child: TabBarView(children: allTabs.map(_tabBody).toList()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBody(_TabEntry tab) {
    final error = _tabErrors[tab.id];
    if (error == null) return tab.body;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _reloadTab(tab.id),
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reloadTab(String tab) => switch (tab) {
    'users' => _loadUsers(),
    'backups' => _loadBackups(),
    'files' => _loadFiles(),
    'settings' => _loadSettings(),
    'tasks' => _loadTasks(),
    'events' => _loadEvents(),
    'updates' => _loadUpdateStatus(),
    _ => Future<void>.value(),
  };
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
  const _UsersTab({required this.users, required this.onRefresh, this.error});

  final List<String>? users;
  final Future<void> Function() onRefresh;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = users;
    if (list == null) {
      if (error == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRefresh,
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      );
    }
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
    this.loading = false,
    this.error,
  });

  final List<BackupEntry>? backups;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreate;
  final Future<void> Function(BackupEntry) onRestore;
  final Future<void> Function(BackupEntry) onDelete;
  final bool busy;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = backups;
    if (list == null) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('Wird geladen…'));
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
    this.loading = false,
    this.error,
  });

  final List<FileEntry>? files;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onCreateFolder;
  final Future<void> Function(FileEntry) onDelete;
  final Future<void> Function(FileEntry) onRename;
  final bool busy;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = files;
    if (list == null) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('Wird geladen…'));
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
    this.loading = false,
    this.error,
  });

  final List<SettingEntry>? settings;
  final Future<void> Function() onRefresh;
  final Future<void> Function(SettingEntry) onEdit;
  final bool busy;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = settings;
    if (list == null) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('Wird geladen…'));
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
                      title: Text(setting.displayName),
                      subtitle: _SettingSubtitle(setting: setting),
                      trailing: IconButton(
                        tooltip: 'Bearbeiten',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: busy || setting.readOnly
                            ? null
                            : () => onEdit(setting),
                      ),
                      onTap: busy || setting.readOnly
                          ? null
                          : () => onEdit(setting),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SettingSubtitle extends StatelessWidget {
  const _SettingSubtitle({required this.setting});

  final SettingEntry setting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = setting.value.isEmpty ? '(leer)' : setting.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (setting.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(setting.description),
          ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (setting.type.isNotEmpty) TextSpan(text: ' • ${setting.type}'),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (setting.key.isNotEmpty && setting.key != setting.displayName)
          Text(
            setting.key,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.outline,
            ),
          ),
      ],
    );
  }
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({
    required this.tasks,
    required this.onRefresh,
    required this.onToggle,
    this.busy = false,
    this.loading = false,
    this.error,
  });

  final List<SchedulerTask>? tasks;
  final Future<void> Function() onRefresh;
  final Future<void> Function(SchedulerTask) onToggle;
  final bool busy;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = tasks;
    if (list == null) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('Wird geladen…'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Keine Tasks vorhanden.')),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                ...list.map(
                  (task) => Card(
                    child: ListTile(
                      leading: Icon(
                        task.enabled ? Icons.schedule : Icons.schedule_outlined,
                        color: task.enabled ? Colors.green : null,
                      ),
                      title: Text(task.name),
                      subtitle: Text(
                        [
                          task.description,
                          task.trigger,
                        ].where((s) => s.isNotEmpty).join(' • '),
                      ),
                      trailing: Switch(
                        value: task.enabled,
                        onChanged: busy ? null : (_) => onToggle(task),
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

class _EventsTab extends StatelessWidget {
  const _EventsTab({
    required this.events,
    required this.onRefresh,
    this.loading = false,
    this.error,
  });

  final List<AmpEvent>? events;
  final Future<void> Function() onRefresh;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final list = events;
    if (list == null) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('Wird geladen…'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: list.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('Keine Einträge.')),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                ...list.map((event) {
                  final color = switch (event.severity.toLowerCase()) {
                    'error' || 'critical' => Colors.redAccent,
                    'warning' => Colors.orange,
                    _ => Colors.blueGrey,
                  };
                  final time = event.timestamp;
                  String two(int v) => v.toString().padLeft(2, '0');
                  final stamp = time == null
                      ? ''
                      : '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.circle, color: color, size: 12),
                      title: Text(event.message),
                      subtitle: Text(
                        [
                          stamp,
                          event.severity,
                        ].where((s) => s.isNotEmpty).join(' • '),
                      ),
                      dense: true,
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------

class _UpdatesTab extends StatelessWidget {
  const _UpdatesTab({
    required this.status,
    required this.onRefresh,
    required this.onRunUpdate,
    this.busy = false,
    this.loading = false,
    this.error,
  });

  final InstanceStatus? status;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRunUpdate;
  final bool busy;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final data = status;
    if (data == null) {
      if (loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        );
      }
      return const Center(child: Text('Wird geladen…'));
    }
    final state = data.state;
    final updating = state == AppState.updating;
    final canUpdate = state.isStopped && state != AppState.undefined;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                updating ? Icons.system_update_alt : Icons.info_outline,
                color: state.color,
              ),
              title: Text(
                updating
                    ? 'Spielserver wird aktualisiert'
                    : 'Spielserver aktualisieren',
              ),
              subtitle: Text('Status: ${state.label}'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            canUpdate
                ? 'AMP aktualisiert die Serverdateien aus der konfigurierten Quelle.'
                : updating
                ? 'Die Aktualisierung läuft.'
                : 'Stoppe den Server vor einer Aktualisierung.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy || !canUpdate ? null : onRunUpdate,
            icon: const Icon(Icons.system_update_alt),
            label: const Text('Update starten'),
          ),
        ],
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    this.module = 'Core',
    required this.method,
    required this.icon,
    required this.label,
  });

  final String method;
  final String module;
  final Icon icon;
  final String label;
}

class _TabEntry {
  const _TabEntry({required this.id, required this.spec, required this.body});

  final String id;
  final _TabSpec spec;
  final Widget body;
}
