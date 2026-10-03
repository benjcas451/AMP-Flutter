import 'dart:convert';

import 'package:amp_control/api/amp_client.dart';
import 'package:amp_control/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<String> calls;
  late List<Map<String, dynamic>> bodies;
  Object instanceActionResult = {'Status': true};
  var sessionCounter = 0;
  var validSessions = <String>{};

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  MockClient fakeFilesAmp() => MockClient((req) async {
    final path = req.url.path;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    calls.add(path);
    bodies.add(body);

    if (path.endsWith('/API/Core/Login')) {
      final sid = 'sid${++sessionCounter}';
      validSessions.add(sid);
      return json({'success': true, 'sessionID': sid});
    }
    if (!validSessions.contains(body['SESSIONID'])) {
      return http.Response('', 401);
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetFiles') {
      return json({
        'Files': [
          {'Name': 'config', 'Path': 'config', 'IsDirectory': true},
          {
            'Name': 'server.properties',
            'Path': 'server.properties',
            'IsDirectory': false,
            'Size': 512,
          },
        ],
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/CreateDirectory' ||
        path == '/API/ADSModule/Servers/mc/API/Core/DeleteFile' ||
        path == '/API/ADSModule/Servers/mc/API/Core/RenameFile') {
      return json({'Status': true});
    }
    return http.Response('not found', 404);
  });

  AmpClient filesClient() => AmpClient(
    baseUrl: 'amp.local:8080/',
    username: 'admin',
    password: 'secret',
    httpClient: fakeFilesAmp(),
  );

  final mockSettings = {
    'ServerName': {
      'Name': 'ServerName',
      'Value': 'My Server',
      'Type': 'String',
      'Description': 'Name of the server shown in the list',
    },
    'MaxPlayers': {
      'Name': 'MaxPlayers',
      'Value': '20',
      'Type': 'Integer',
      'Description': 'Maximum number of players',
    },
  };

  MockClient fakeSettingsAmp() => MockClient((req) async {
    final path = req.url.path;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    calls.add(path);
    bodies.add(body);

    if (path.endsWith('/API/Core/Login')) {
      final sid = 'sid${++sessionCounter}';
      validSessions.add(sid);
      return json({'success': true, 'sessionID': sid});
    }
    if (!validSessions.contains(body['SESSIONID'])) {
      return http.Response('', 401);
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetSettings') {
      return json(mockSettings);
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/SetSetting') {
      return json({'Status': true});
    }
    return http.Response('not found', 404);
  });

  AmpClient settingsClient() => AmpClient(
    baseUrl: 'amp.local:8080/',
    username: 'admin',
    password: 'secret',
    httpClient: fakeSettingsAmp(),
  );

  MockClient fakeAmp() => MockClient((req) async {
    final path = req.url.path;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    calls.add(path);
    bodies.add(body);

    if (path.endsWith('/API/Core/Login')) {
      if (body['username'] == 'admin' && body['password'] == 'secret') {
        final sid = 'sid${++sessionCounter}';
        validSessions.add(sid);
        return json({'success': true, 'sessionID': sid});
      }
      return json({'success': false, 'resultReason': 'Bad credentials'});
    }
    if (path == '/API/Core/GetModuleInfo') {
      return json({'Author': 'CubeCoders Limited', 'AppName': 'ADS'});
    }
    if (!validSessions.contains(body['SESSIONID'])) {
      return http.Response('', 401);
    }
    if (path == '/API/ADSModule/GetInstances') {
      return json({
        'result': [
          {
            'AvailableInstances': [
              {
                'InstanceID': 'ads',
                'InstanceName': 'ADS01',
                'Module': 'ADS',
                'Running': true,
              },
              {
                'InstanceID': 'mc',
                'InstanceName': 'Minecraft01',
                'FriendlyName': 'Survival',
                'Module': 'Minecraft',
                'Running': true,
                'AppState': 40,
                'Metrics': {
                  'CPU Usage': {
                    'RawValue': 12,
                    'MaxValue': 100,
                    'Percent': 12,
                    'Units': '%',
                  },
                },
              },
            ],
          },
        ],
      });
    }
    if (path == '/API/ADSModule/StartInstance' ||
        path == '/API/ADSModule/StopInstance') {
      return json(instanceActionResult);
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetUpdates') {
      return json({
        'Status': {'State': 10, 'Uptime': '00:00:00', 'Metrics': {}},
        'ConsoleEntries': [
          {
            'Timestamp': '/Date(1700000000000)/',
            'Source': 'Console',
            'Type': 'Console',
            'Contents': 'Done (3.2s)!',
          },
        ],
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetUserList') {
      return json({
        'result': {'uuid-2': 'Steve', 'uuid-1': 'Alex'},
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetBackups') {
      return json({
        'Backups': [
          {
            'BackupName': 'world-2024-06-01',
            'Created': '2024-06-01T12:00:00Z',
            'Size': 2048,
          },
        ],
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/CreateBackup' ||
        path == '/API/ADSModule/Servers/mc/API/Core/RestoreBackup' ||
        path == '/API/ADSModule/Servers/mc/API/Core/DeleteBackup') {
      return json({'Status': true});
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/Start') {
      return json({'Status': false, 'Reason': 'EULA not accepted'});
    }
    return http.Response('not found', 404);
  });

  setUp(() {
    calls = [];
    bodies = [];
    instanceActionResult = {'Status': true};
    sessionCounter = 0;
    validSessions = {};
  });

  AmpClient client({String password = 'secret'}) => AmpClient(
    baseUrl: 'amp.local:8080/',
    username: 'admin',
    password: password,
    httpClient: fakeAmp(),
  );

  test('normalizes URLs', () {
    expect(
      AmpClient.normalizeUrl(' amp.local:8080/ '),
      'http://amp.local:8080',
    );
    expect(AmpClient.normalizeUrl('https://x.de//'), 'https://x.de');
  });

  test('testConnection logs in', () async {
    expect(await client().testConnection(), 'ADS');
  });

  test('wrong password yields readable error', () async {
    expect(
      client(password: 'nope').testConnection(),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          contains('Bad credentials'),
        ),
      ),
    );
  });

  test('lists instances without the ADS itself', () async {
    final list = await client().getInstances();
    expect(list.map((i) => i.displayName), ['Survival']);
    expect(list.single.appState, AppState.ready);
    expect(list.single.metrics['CPU Usage']!.valueText, '12 %');
  });

  test('instance calls use the ADS proxy with their own session', () async {
    final c = client();
    final u = await c.getUpdates('mc');
    expect(u.status!.state, AppState.stopped);
    expect(u.console.single.contents, 'Done (3.2s)!');
    expect(u.console.single.timestamp, isNotNull);
    expect(calls, [
      '/API/ADSModule/Servers/mc/API/Core/Login',
      '/API/ADSModule/Servers/mc/API/Core/GetUpdates',
    ]);
    expect(await c.getUsers('mc'), ['Alex', 'Steve']);
  });

  test('re-logs in once when the session expired', () async {
    final c = client();
    await c.getInstances();
    validSessions.clear();
    await c.getInstances();
    expect(calls.where((p) => p.endsWith('Login')).length, 2);
  });

  test('failed actions surface the reason', () async {
    expect(
      client().startServer('mc'),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'EULA not accepted',
        ),
      ),
    );
  });

  for (final start in [true, false]) {
    final method = start ? 'StartInstance' : 'StopInstance';
    test('$method uses the ADS session and internal instance name', () async {
      final c = client();
      final instance = (await c.getInstances()).single;
      calls.clear();
      bodies.clear();
      if (start) {
        await c.startInstanceProcess(instance);
      } else {
        await c.stopInstanceProcess(instance);
      }
      expect(calls, ['/API/ADSModule/$method']);
      expect(bodies.single, {
        'InstanceName': 'Minecraft01',
        'SESSIONID': 'sid1',
      });
      c.close();
    });

    test('$method clears cached instance sessions', () async {
      final c = client();
      final instance = (await c.getInstances()).single;
      await c.getUpdates(instance.id);
      if (start) {
        await c.startInstanceProcess(instance);
      } else {
        await c.stopInstanceProcess(instance);
      }
      await c.getUpdates(instance.id);
      expect(
        calls.where((p) => p == '/API/ADSModule/Servers/mc/API/Core/Login'),
        hasLength(2),
      );
      expect(calls.where((p) => p == '/API/Core/Login'), hasLength(1));
      c.close();
    });
  }

  test(
    'backup list and backup actions are handled through the instance API',
    () async {
      final c = client();
      final backupName = 'world-2024-06-01';
      instanceActionResult = {'Status': true};

      final backups = await c.getBackups('mc');
      expect(backups.single.name, backupName);
      expect(backups.single.sizeBytes, 2048);

      await c.createBackup('mc', 'manual-backup');
      await c.restoreBackup('mc', backupName);
      await c.deleteBackup('mc', backupName);

      expect(calls.where((p) => p.endsWith('/API/Core/GetBackups')).length, 1);
      expect(
        calls.where((p) => p.endsWith('/API/Core/CreateBackup')).length,
        1,
      );
      expect(
        calls.where((p) => p.endsWith('/API/Core/RestoreBackup')).length,
        1,
      );
      expect(
        calls.where((p) => p.endsWith('/API/Core/DeleteBackup')).length,
        1,
      );
      c.close();
    },
  );

  test('backup names are trimmed before the request is sent', () async {
    final c = client();
    await c.createBackup('mc', '  manual-backup  ');
    expect(bodies.last['BackupName'], 'manual-backup');
    c.close();
  });

  test('empty backup names are rejected before the request is sent', () async {
    final c = client();
    expect(
      () => c.createBackup('mc', '   '),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Backup-Name darf nicht leer sein.',
        ),
      ),
    );
    expect(
      () => c.restoreBackup('mc', ''),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Backup-Name darf nicht leer sein.',
        ),
      ),
    );
    expect(
      () => c.deleteBackup('mc', '  '),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Backup-Name darf nicht leer sein.',
        ),
      ),
    );
    c.close();
  });

  test('failed instance stop surfaces the ADS reason', () async {
    final c = client();
    final instance = (await c.getInstances()).single;
    instanceActionResult = {'Status': false, 'Reason': 'Instance stop denied'};
    await expectLater(
      c.stopInstanceProcess(instance),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Instance stop denied',
        ),
      ),
    );
    c.close();
  });

  test('boolean false is reported as an action failure', () async {
    final c = client();
    final instance = (await c.getInstances()).single;
    instanceActionResult = {'result': false};
    await expectLater(
      c.startInstanceProcess(instance),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'StartInstance fehlgeschlagen.',
        ),
      ),
    );
    c.close();
  });

  test('lists files from the instance file API', () async {
    final c = filesClient();
    final files = await c.getFiles('mc');
    expect(files, hasLength(2));
    expect(files[0].isDirectory, isTrue);
    expect(files[1].sizeBytes, 512);
    c.close();
  });

  test('file actions use the instance API', () async {
    final c = filesClient();
    await c.createDirectory('mc', 'plugins/new');
    await c.deleteFile('mc', 'server.properties');
    await c.renameFile('mc', 'server.properties', 'server-old.properties');
    expect(
      calls.where((p) => p.endsWith('/API/Core/CreateDirectory')).length,
      1,
    );
    expect(calls.where((p) => p.endsWith('/API/Core/DeleteFile')).length, 1);
    expect(calls.where((p) => p.endsWith('/API/Core/RenameFile')).length, 1);
    c.close();
  });

  test('file paths are validated before requests are sent', () async {
    final c = filesClient();
    expect(
      () => c.createDirectory('mc', '   '),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Pfad darf nicht leer sein.',
        ),
      ),
    );
    expect(
      () => c.renameFile('mc', 'plugins/a.cfg', ''),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Umbenennen benötigt gültige Dateinamen.',
        ),
      ),
    );
    c.close();
  });

  test('lists settings from the instance settings API', () async {
    final c = settingsClient();
    final settings = await c.getSettings('mc');
    expect(settings, hasLength(2));
    expect(settings[0].name, 'MaxPlayers');
    expect(settings[1].name, 'ServerName');
    c.close();
  });

  test('setSetting sends the value through the instance API', () async {
    final c = settingsClient();
    await c.setSetting('mc', 'ServerName', 'New Server Name');
    expect(calls.where((p) => p.endsWith('/API/Core/SetSetting')).length, 1);
    expect(bodies.last['SettingName'], 'ServerName');
    expect(bodies.last['Value'], 'New Server Name');
    c.close();
  });

  test('setting name is validated before requests are sent', () async {
    final c = settingsClient();
    expect(
      () => c.setSetting('mc', '', 'value'),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Setting-Name darf nicht leer sein.',
        ),
      ),
    );
    c.close();
  });

  MockClient fakeSchedulerAndEventsAmp() => MockClient((req) async {
    final path = req.url.path;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    calls.add(path);
    bodies.add(body);

    if (path.endsWith('/API/Core/Login')) {
      final sid = 'sid${++sessionCounter}';
      validSessions.add(sid);
      return json({'success': true, 'sessionID': sid});
    }
    if (!validSessions.contains(body['SESSIONID'])) {
      return http.Response('', 401);
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetTasks') {
      return json({
        'task-1': {
          'Id': 'task-1',
          'Name': 'Nightly Backup',
          'Description': 'Creates a backup every night',
          'Trigger': 'Daily at 03:00',
          'Enabled': true,
        },
        'task-2': {
          'Id': 'task-2',
          'Name': 'Restart server',
          'Description': '',
          'Trigger': 'Every 12 hours',
          'Enabled': false,
        },
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/SetTaskEnabled') {
      return json({'Status': true});
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetEventLog') {
      return json({
        'event-1': {
          'Message': 'Backup completed',
          'Timestamp': '/Date(1700000000000)/',
          'Severity': 'Info',
        },
        'event-2': {
          'Message': 'Task failed',
          'Timestamp': '/Date(1700000100000)/',
          'Severity': 'Warning',
        },
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/GetUpdateStatus') {
      return json({
        'UpdateAvailable': true,
        'CurrentVersion': '1.0.0',
        'LatestVersion': '1.2.0',
      });
    }
    if (path == '/API/ADSModule/Servers/mc/API/Core/RunUpdate') {
      return json({'Status': true});
    }
    return http.Response('not found', 404);
  });

  AmpClient schedulerClient() => AmpClient(
    baseUrl: 'amp.local:8080/',
    username: 'admin',
    password: 'secret',
    httpClient: fakeSchedulerAndEventsAmp(),
  );

  test('lists scheduler tasks', () async {
    final c = schedulerClient();
    final tasks = await c.getTasks('mc');
    expect(tasks, hasLength(2));
    expect(tasks[0].name, 'Nightly Backup');
    expect(tasks[1].name, 'Restart server');
    c.close();
  });

  test('task enabled can be toggled', () async {
    final c = schedulerClient();
    await c.setTaskEnabled('mc', 'task-1', false);
    expect(
      calls.where((p) => p.endsWith('/API/Core/SetTaskEnabled')).length,
      1,
    );
    expect(bodies.last['TaskID'], 'task-1');
    expect(bodies.last['Enabled'], false);
    c.close();
  });

  test('task ID is validated before requests are sent', () async {
    final c = schedulerClient();
    expect(
      () => c.setTaskEnabled('mc', '', false),
      throwsA(
        isA<AmpException>().having(
          (e) => e.message,
          'message',
          'Task-ID darf nicht leer sein.',
        ),
      ),
    );
    c.close();
  });

  test('lists events sorted by timestamp descending', () async {
    final c = schedulerClient();
    final events = await c.getEvents('mc');
    expect(events, hasLength(2));
    expect(events[0].message, 'Task failed');
    expect(events[1].message, 'Backup completed');
    c.close();
  });

  test('returns update status', () async {
    final c = schedulerClient();
    final status = await c.getUpdateStatus('mc');
    expect(status['UpdateAvailable'], true);
    expect(status['LatestVersion'], '1.2.0');
    c.close();
  });

  test('run update uses the instance API', () async {
    final c = schedulerClient();
    await c.runUpdate('mc');
    expect(calls.where((p) => p.endsWith('/API/Core/RunUpdate')).length, 1);
    c.close();
  });
}
