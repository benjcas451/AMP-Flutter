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
}
