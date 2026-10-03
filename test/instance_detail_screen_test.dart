import 'dart:convert';

import 'package:amp_control/api/amp_client.dart';
import 'package:amp_control/api/models.dart';
import 'package:amp_control/screens/instance_detail_screen.dart';
import 'package:amp_control/services/settings_store.dart';
import 'package:amp_control/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class _Model extends AppModel {
  _Model(this.api) : super(SettingsStore());
  final AmpClient api;
  @override
  AmpClient get client => api;
}

void main() {
  late AmpClient client;
  late _Model model;
  late Map<String, Object?> responses;
  late List<http.Request> requests;
  var missingBackupInOne = false;

  setUp(() {
    missingBackupInOne = false;
    requests = [];
    responses = {
      'Core/GetUpdates': {
        'Status': {'State': 10},
        'ConsoleEntries': [],
      },
      'Core/GetStatus': {'State': 10},
      'Core/GetUserList': {},
      'LocalFileBackupPlugin/GetBackups': [],
      'FileManagerPlugin/GetDirectoryListing': [],
      'Core/GetSettingsSpec': {},
      'Core/GetScheduleData': {'PopulatedTriggers': []},
      'Core/GetAuditLogEntries': [],
      'Core/UpdateApplication': {'Status': true},
    };
    client = AmpClient(
      baseUrl: 'http://amp.local',
      username: '',
      password: '',
      httpClient: MockClient((request) async {
        requests.add(request);
        final method = request.url.path.split('/API/').last;
        final Object? response;
        if (method == 'Core/Login') {
          response = {'success': true, 'sessionID': 'session'};
        } else if (missingBackupInOne &&
            request.url.path.contains('/Servers/one/') &&
            method == 'LocalFileBackupPlugin/GetBackups') {
          response = {
            'Title': 'MissingMethodException',
            'Message': 'Missing method',
            'StackTrace': '',
          };
        } else {
          if (method == 'Core/UpdateApplication') {
            responses['Core/GetStatus'] = {'State': 100};
            responses['Core/GetUpdates'] = {
              'Status': {'State': 100},
              'ConsoleEntries': [],
            };
          }
          response = responses[method];
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    model = _Model(client);
  });
  tearDown(() {
    model.dispose();
    client.close();
  });

  Future<void> showScreen(WidgetTester tester, [String id = 'one']) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>.value(
        value: model,
        child: MaterialApp(
          key: ValueKey(id),
          home: InstanceDetailScreen(
            instance: AmpInstance.fromJson({
              'InstanceID': id,
              'InstanceName': id,
              'Running': true,
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String label) async {
    final tab = find.widgetWithText(Tab, label);
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('player loading errors are visible and can be retried', (
    tester,
  ) async {
    responses['Core/GetUserList'] = {
      'Status': false,
      'Reason': 'Spielerliste nicht erreichbar',
    };
    await showScreen(tester);
    await select(tester, 'Spieler');
    expect(find.text('Spielerliste nicht erreichbar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    responses['Core/GetUserList'] = {'uuid': 'Alex'};
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
  });

  testWidgets(
    'unsupported plugins in one instance do not hide tabs in another',
    (tester) async {
      missingBackupInOne = true;
      await showScreen(tester);
      expect(find.widgetWithText(Tab, 'Backups'), findsNothing);
      await showScreen(tester, 'two');
      expect(find.widgetWithText(Tab, 'Backups'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the game update tab offers the application update and tracks progress',
    (tester) async {
      await showScreen(tester);
      expect(
        requests.where((r) => r.url.path.endsWith('/Core/Login')),
        hasLength(1),
      );
      await select(tester, 'Updates');
      expect(find.text('Status: Gestoppt'), findsOneWidget);
      await tester.tap(find.text('Update starten'));
      await tester.pumpAndSettle();
      expect(find.text('Spielserver aktualisieren?'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Update starten').last,
      );
      await tester.pumpAndSettle();
      expect(
        requests.where((r) => r.url.path.endsWith('/Core/UpdateApplication')),
        hasLength(1),
      );
      expect(find.text('Spielserver wird aktualisiert'), findsOneWidget);
      expect(find.text('Status: Aktualisiert'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Update starten'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
