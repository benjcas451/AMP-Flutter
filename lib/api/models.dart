import 'package:flutter/material.dart';

/// AMP application states (`ApplicationState` enum in AMP).
enum AppState {
  undefined(0, 'Unbekannt', Colors.grey),
  stopped(10, 'Gestoppt', Colors.red),
  preStart(20, 'Startet', Colors.orange),
  configuring(30, 'Konfiguriert', Colors.orange),
  starting(35, 'Startet', Colors.orange),
  ready(40, 'Läuft', Colors.green),
  restarting(45, 'Neustart', Colors.orange),
  stopping(50, 'Stoppt', Colors.orange),
  preparingForSleep(60, 'Schlafvorbereitung', Colors.blueGrey),
  sleeping(70, 'Schläft', Colors.blueGrey),
  waiting(80, 'Wartet', Colors.orange),
  installing(90, 'Installiert', Colors.blue),
  updating(100, 'Aktualisiert', Colors.blue),
  awaitingUserInput(200, 'Wartet auf Eingabe', Colors.amber),
  failed(999, 'Fehler', Colors.red);

  const AppState(this.code, this.label, this.color);
  final int code;
  final String label;
  final Color color;

  static AppState fromCode(dynamic code) {
    final c = code is int ? code : int.tryParse('$code') ?? 0;
    return AppState.values.firstWhere(
      (s) => s.code == c,
      orElse: () => AppState.undefined,
    );
  }

  bool get isRunning => this == AppState.ready;
  bool get isStopped =>
      this == AppState.stopped ||
      this == AppState.failed ||
      this == AppState.undefined;
  bool get isBusy => !isRunning && !isStopped && this != AppState.sleeping;
}

class Metric {
  Metric({
    required this.name,
    required this.raw,
    required this.max,
    required this.percent,
    required this.units,
  });

  factory Metric.fromJson(String name, Map<String, dynamic> j) => Metric(
    name: name,
    raw: (j['RawValue'] as num?) ?? 0,
    max: (j['MaxValue'] as num?) ?? 0,
    percent: (j['Percent'] as num?) ?? 0,
    units: j['Units']?.toString() ?? '',
  );

  final String name;
  final num raw;
  final num max;
  final num percent;
  final String units;

  String get label => switch (name) {
    'CPU Usage' => 'CPU',
    'Memory Usage' => 'RAM',
    'Active Users' => 'Spieler',
    _ => name,
  };

  String get valueText {
    if (units == '%') return '$raw %';
    if (max > 0) return '$raw / $max $units'.trim();
    return '$raw $units'.trim();
  }

  double get fraction => (percent / 100).clamp(0, 1).toDouble();
}

Map<String, Metric> _parseMetrics(dynamic m) {
  if (m is! Map) return const {};
  return {
    for (final e in m.entries)
      if (e.value is Map)
        e.key.toString(): Metric.fromJson(
          e.key.toString(),
          Map<String, dynamic>.from(e.value),
        ),
  };
}

class AmpInstance {
  AmpInstance({
    required this.id,
    required this.instanceName,
    required this.friendlyName,
    required this.module,
    required this.moduleDisplayName,
    required this.running,
    required this.appState,
    required this.metrics,
  });

  factory AmpInstance.fromJson(Map<String, dynamic> j) => AmpInstance(
    id: j['InstanceID']?.toString() ?? '',
    instanceName: j['InstanceName']?.toString() ?? '',
    friendlyName: j['FriendlyName']?.toString() ?? '',
    module: j['Module']?.toString() ?? '',
    moduleDisplayName: j['ModuleDisplayName']?.toString() ?? '',
    running: j['Running'] == true,
    appState: AppState.fromCode(j['AppState']),
    metrics: _parseMetrics(j['Metrics']),
  );

  final String id;
  final String instanceName;
  final String friendlyName;
  final String module;
  final String moduleDisplayName;

  /// Whether the AMP instance process runs (required for any instance call).
  final bool running;
  final AppState appState;
  final Map<String, Metric> metrics;

  String get displayName =>
      friendlyName.isNotEmpty ? friendlyName : instanceName;

  String get subtitle =>
      moduleDisplayName.isNotEmpty ? moduleDisplayName : module;
}

class InstanceStatus {
  InstanceStatus({
    required this.state,
    required this.uptime,
    required this.metrics,
  });

  factory InstanceStatus.fromJson(Map<String, dynamic> j) => InstanceStatus(
    state: AppState.fromCode(j['State']),
    uptime: j['Uptime']?.toString() ?? '',
    metrics: _parseMetrics(j['Metrics']),
  );

  final AppState state;
  final String uptime;
  final Map<String, Metric> metrics;
}

class SettingEntry {
  SettingEntry({
    required this.name,
    required this.value,
    required this.type,
    required this.description,
  });

  factory SettingEntry.fromJson(Map<String, dynamic> j) => SettingEntry(
    name: j['Name']?.toString() ?? '',
    value: j['Value']?.toString() ?? '',
    type: j['Type']?.toString() ?? '',
    description: j['Description']?.toString() ?? '',
  );

  final String name;
  final String value;
  final String type;
  final String description;
}

class ConsoleEntry {
  ConsoleEntry({
    required this.timestamp,
    required this.source,
    required this.type,
    required this.contents,
  });

  factory ConsoleEntry.fromJson(Map<String, dynamic> j) => ConsoleEntry(
    timestamp: _parseAmpDate(j['Timestamp']),
    source: j['Source']?.toString() ?? '',
    type: j['Type']?.toString() ?? '',
    contents: j['Contents']?.toString() ?? '',
  );

  final DateTime? timestamp;
  final String source;
  final String type;
  final String contents;
}

class BackupEntry {
  BackupEntry({required this.name, this.createdAt, this.sizeBytes = 0});

  factory BackupEntry.fromJson(Map<String, dynamic> j) => BackupEntry(
    name: j['BackupName']?.toString() ?? j['Name']?.toString() ?? '',
    createdAt: j['Created']?.toString() ?? j['CreatedAt']?.toString(),
    sizeBytes: _parseBackupSize(j['Size']),
  );

  final String name;
  final String? createdAt;
  final int sizeBytes;

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class FileEntry {
  FileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedAt,
  });

  factory FileEntry.fromJson(Map<String, dynamic> j) => FileEntry(
    name: j['Name']?.toString() ?? '',
    path: j['Path']?.toString() ?? '',
    isDirectory:
        j['IsDirectory'] == true ||
        j['IsDirectory'] == 'true' ||
        j['IsFolder'] == true ||
        j['IsFolder'] == 'true' ||
        j['Type']?.toString().toLowerCase() == 'directory',
    sizeBytes: _parseBackupSize(j['SizeBytes'] ?? j['Size']),
    modifiedAt: _parseAmpDate(
      j['Modified'] ??
          j['ModifiedAt'] ??
          j['LastModified'] ??
          j['LastWriteTime'],
    ),
  );

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024) return '$sizeBytes B';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

int _parseBackupSize(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    final parsed = int.tryParse(trimmed);
    if (parsed != null) return parsed;
    final numFromText = double.tryParse(trimmed);
    if (numFromText != null) return numFromText.toInt();
  }
  return 0;
}

/// AMP sends dates either as ISO strings or as "/Date(1700000000000)/".
DateTime? _parseAmpDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  final ms = RegExp(r'/Date\((-?\d+)').firstMatch(s);
  if (ms != null) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(ms.group(1)!))
        .toLocal();
  }
  return DateTime.tryParse(s)?.toLocal();
}

class InstanceUpdates {
  InstanceUpdates({required this.status, required this.console});

  factory InstanceUpdates.fromJson(Map<String, dynamic> j) {
    final entries = j['ConsoleEntries'];
    return InstanceUpdates(
      status: j['Status'] is Map
          ? InstanceStatus.fromJson(Map<String, dynamic>.from(j['Status']))
          : null,
      console: entries is List
          ? entries
                .map(
                  (e) => ConsoleEntry.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const [],
    );
  }

  final InstanceStatus? status;
  final List<ConsoleEntry> console;
}
