import 'dart:async';
import 'dart:convert';

import 'package:amp_control/api/amp_client.dart';
import 'package:amp_control/api/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  late AmpClient client;
  late List<http.Request> requests;
  late FutureOr<http.Response> Function(http.Request) respond;

  setUp(() {
    requests = [];
    respond = (_) => _json([]);
    client = AmpClient(
      baseUrl: 'http://amp.local',
      username: 'admin',
      password: 'secret',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/Core/Login')) {
          return _json({'success': true, 'sessionID': 'session'});
        }
        return respond(request);
      }),
    );
  });
  tearDown(() => client.close());

  final getters = <String, Future<Object?> Function(AmpClient)>{
    'instances': (c) => c.getInstances(),
    'status': (c) => c.getStatus('mc'),
    'updates': (c) => c.getUpdates('mc'),
    'users': (c) => c.getUsers('mc'),
    'backups': (c) => c.getBackups('mc'),
    'files': (c) => c.getFiles('mc'),
    'settings': (c) => c.getSettings('mc'),
    'schedule': (c) => c.getTasks('mc'),
    'events': (c) => c.getEvents('mc'),
    'application update status': (c) => c.getUpdateStatus('mc'),
  };

  for (final getter in getters.entries) {
    test('${getter.key}: rejects unexpected scalars and null', () async {
      for (final value in ['unexpected', null]) {
        respond = (_) => _json(value);
        await expectLater(
          getter.value(client),
          throwsA(
            isA<AmpException>().having(
              (e) => e.message,
              'message',
              contains('Ungültige Antwort'),
            ),
          ),
        );
      }
    });
    test('${getter.key}: preserves the reason of a failed read', () async {
      respond = (_) => _json({'Status': false, 'Reason': 'Access denied'});
      await expectLater(
        getter.value(client),
        throwsA(
          isA<AmpException>().having(
            (e) => e.message,
            'message',
            'Access denied',
          ),
        ),
      );
    });
  }

  test(
    'bad list entries surface an AmpException rather than a TypeError',
    () async {
      respond = (_) => _json([null]);
      for (final read in [
        () => client.getInstances(),
        () => client.getFiles('mc'),
        () => client.getBackups('mc'),
        () => client.getEvents('mc'),
      ]) {
        await expectLater(read(), throwsA(isA<AmpException>()));
      }
    },
  );

  test(
    'invalid metrics and console entries are reported as read errors',
    () async {
      respond = (_) => _json({
        'State': 40,
        'Metrics': {
          'CPU Usage': {'RawValue': 'invalid'},
        },
      });
      await expectLater(client.getStatus('mc'), throwsA(isA<AmpException>()));
      respond = (_) => _json({
        'Status': {'State': 40},
        'ConsoleEntries': [null],
      });
      await expectLater(client.getUpdates('mc'), throwsA(isA<AmpException>()));
      respond = (_) => _json({'State': 'invalid'});
      await expectLater(client.getStatus('mc'), throwsA(isA<AmpException>()));
    },
  );

  test('valid empty collections stay empty', () async {
    respond = (_) => _json([]);
    expect(await client.getInstances(), isEmpty);
    expect(await client.getFiles('mc'), isEmpty);
    expect(await client.getBackups('mc'), isEmpty);
    expect(await client.getEvents('mc'), isEmpty);
    respond = (_) => _json({});
    expect(await client.getUsers('mc'), isEmpty);
    expect(await client.getSettings('mc'), isEmpty);
    respond = (_) => _json({'PopulatedTriggers': []});
    expect(await client.getTasks('mc'), isEmpty);
  });

  test('backup manifests preserve IDs, dates and sizes', () async {
    respond = (_) => _json([
      {
        'Id': 'backup-id',
        'Name': 'Daily backup',
        'Timestamp': '2026-10-03T09:00:00Z',
        'TotalSizeBytes': 4096,
      },
    ]);
    final backup = (await client.getBackups('mc')).single;
    expect(backup.id, 'backup-id');
    expect(backup.name, 'Daily backup');
    expect(backup.createdAt, '2026-10-03T09:00:00Z');
    expect(backup.sizeBytes, 4096);
    respond = (_) => _json({'Status': true});
    await client.restoreBackup('mc', backup.id);
    expect(jsonDecode(requests.last.body)['BackupId'], 'backup-id');
    await client.deleteBackup('mc', backup.id);
    expect(
      requests.last.url.path,
      endsWith('/LocalFileBackupPlugin/DeleteLocalBackup'),
    );
    expect(jsonDecode(requests.last.body)['BackupId'], 'backup-id');
  });

  test(
    'directory listings derive paths and distinguish file and folder actions',
    () async {
      respond = (_) => _json([
        {'Filename': 'config.yml', 'SizeBytes': 123},
      ]);
      final file = (await client.getFiles('mc', directory: 'plugins/')).single;
      expect(file.name, 'config.yml');
      expect(file.path, 'plugins/config.yml');
      expect(jsonDecode(requests.last.body)['Dir'], 'plugins/');
      respond = (_) => _json({'Status': true});
      await client.deleteFile('mc', 'plugins', isDirectory: true);
      expect(
        requests.last.url.path,
        endsWith('/FileManagerPlugin/TrashDirectory'),
      );
      expect(jsonDecode(requests.last.body)['DirectoryName'], 'plugins');
      await client.renameFile(
        'mc',
        'plugins',
        'plugins-old',
        isDirectory: true,
      );
      expect(
        requests.last.url.path,
        endsWith('/FileManagerPlugin/RenameDirectory'),
      );
      expect(jsonDecode(requests.last.body)['oldDirectory'], 'plugins');
      expect(jsonDecode(requests.last.body)['NewDirectoryName'], 'plugins-old');
    },
  );

  test(
    'grouped settings retain node IDs, current values and read-only flags',
    () async {
      respond = (_) => _json({
        'Minecraft': [
          {
            'Node': 'MinecraftModule.Server.MOTD',
            'Name': 'Server message',
            'CurrentValue': '  hello  ',
            'ValType': 'String',
            'ReadOnly': true,
          },
        ],
      });
      final setting = (await client.getSettings('mc')).single;
      expect(setting.node, 'MinecraftModule.Server.MOTD');
      expect(setting.value, '  hello  ');
      expect(setting.readOnly, isTrue);
      respond = (_) => _json({'Status': true});
      await client.setSetting('mc', setting.node, '  new message  ');
      expect(jsonDecode(requests.last.body)['node'], setting.node);
      expect(jsonDecode(requests.last.body)['value'], '  new message  ');
    },
  );

  test(
    'scheduler lists populated triggers rather than running tasks',
    () async {
      respond = (_) => _json({
        'PopulatedTriggers': [
          {
            'Id': 'trigger',
            'Description': 'Daily backup',
            'TriggerType': 'TimeInterval',
            'EnabledState': 2,
            'Tasks': [
              {'TaskMethodName': 'LocalFileBackupPlugin.TakeBackup'},
            ],
          },
        ],
      });
      final task = (await client.getTasks('mc')).single;
      expect(requests.last.url.path, endsWith('/Core/GetScheduleData'));
      expect(task.id, 'trigger');
      expect(task.name, 'Daily backup');
      expect(task.enabled, isTrue);
      expect(task.description, 'LocalFileBackupPlugin.TakeBackup');
      respond = (_) => _json({'Status': true});
      await client.setTaskEnabled('mc', task.id, false);
      expect(requests.last.url.path, endsWith('/Core/SetTriggerEnabled'));
      expect(jsonDecode(requests.last.body)['Id'], 'trigger');
    },
  );

  test(
    'audit log requests are bounded and timestamps without a value sort last',
    () async {
      respond = (_) => _json([
        {'Message': 'Unknown date'},
        {'Message': 'Old', 'Timestamp': '/Date(1700000000000)/'},
        {'Message': 'New', 'Timestamp': '/Date(1700000100000)/'},
      ]);
      final entries = await client.getEvents('mc');
      expect(entries.map((e) => e.message), ['New', 'Old', 'Unknown date']);
      expect(jsonDecode(requests.last.body)['Before'], isNull);
      expect(jsonDecode(requests.last.body)['Count'], 100);
    },
  );

  for (final stackTrace in [false, true]) {
    test(
      'missing methods are scoped to their module and instance ($stackTrace)',
      () async {
        respond = (_) => _json({
          'Title': 'MissingMethodException',
          'Message': 'Missing method',
          if (stackTrace) 'StackTrace': 'trace',
        }, 500);
        await expectLater(
          client.getBackups('one'),
          throwsA(isA<AmpMethodUnavailable>()),
        );
        expect(
          client.isMethodSupported(
            'GetBackups',
            module: 'LocalFileBackupPlugin',
            instanceId: 'one',
          ),
          isFalse,
        );
        expect(
          client.isMethodSupported(
            'GetBackups',
            module: 'LocalFileBackupPlugin',
            instanceId: 'two',
          ),
          isTrue,
        );
        expect(
          client.isMethodSupported(
            'GetBackups',
            module: 'Core',
            instanceId: 'one',
          ),
          isTrue,
        );
        respond = (_) => _json([]);
        await client.getBackups('one');
        expect(
          client.isMethodSupported(
            'GetBackups',
            module: 'LocalFileBackupPlugin',
            instanceId: 'one',
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'missing files and configuration do not mark API methods unsupported',
    () async {
      respond = (_) => _json({
        'Title': 'Missing configuration',
        'Message': 'File not found',
      });
      await expectLater(client.getFiles('mc'), throwsA(isA<AmpException>()));
      expect(
        client.isMethodSupported(
          'GetDirectoryListing',
          module: 'FileManagerPlugin',
          instanceId: 'mc',
        ),
        isTrue,
      );
    },
  );

  test('capability tracking also applies after a session retry', () async {
    var count = 0;
    respond = (_) => ++count == 1
        ? http.Response('', 401)
        : _json({'Title': 'Missing Method', 'Message': 'Missing method'});
    await expectLater(
      client.getTasks('mc'),
      throwsA(isA<AmpMethodUnavailable>()),
    );
    expect(
      client.isMethodSupported('GetScheduleData', instanceId: 'mc'),
      isFalse,
    );
    expect(
      requests.where((r) => r.url.path.endsWith('/Core/Login')),
      hasLength(2),
    );
  });

  test('parallel instance reads share one login and session', () async {
    final gate = Completer<http.Response>();
    client.close();
    client = AmpClient(
      baseUrl: 'http://amp.local',
      username: '',
      password: '',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/Core/Login')) return gate.future;
        return _json({});
      }),
    );
    final pending = List.generate(6, (_) => client.getUsers('mc'));
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));
    gate.complete(_json({'success': true, 'sessionID': 'shared'}));
    await Future.wait(pending);
    expect(
      requests.skip(1).map((r) => jsonDecode(r.body)['SESSIONID']),
      everyElement('shared'),
    );
  });

  test(
    'game updates use application state and never call AMP update endpoints',
    () async {
      respond = (_) => _json({'State': 100});
      expect((await client.getUpdateStatus('mc')).state, AppState.updating);
      respond = (_) => _json({'Status': true});
      await client.runUpdate('mc');
      expect(requests.last.url.path, endsWith('/Core/UpdateApplication'));
      expect(
        requests.any(
          (r) =>
              r.url.path.endsWith('/GetUpdateInfo') ||
              r.url.path.endsWith('/UpdateAMPInstance'),
        ),
        isFalse,
      );
    },
  );
}
