import 'dart:async';

import 'package:amp_control/api/amp_client.dart';
import 'package:amp_control/api/models.dart';
import 'package:amp_control/screens/instances_screen.dart';
import 'package:amp_control/services/settings_store.dart';
import 'package:amp_control/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Client extends AmpClient {
  _Client() : super(baseUrl: 'http://amp.local', username: '', password: '');

  bool running = false;
  String friendlyName = 'Survival';
  bool updateImmediately = true;
  String? actionError;
  Completer<void>? actionGate;
  int starts = 0;
  int stops = 0;

  @override
  Future<List<AmpInstance>> getInstances() async => [
    AmpInstance.fromJson({
      'InstanceID': 'mc',
      'InstanceName': 'Minecraft01',
      'FriendlyName': friendlyName,
      'Module': 'Minecraft',
      'Running': running,
      'AppState': 10,
    }),
  ];

  Future<void> _change(bool value) async {
    if (actionGate != null) await actionGate!.future;
    if (actionError != null) throw AmpException(actionError!);
    if (updateImmediately) running = value;
  }

  @override
  Future<void> startInstanceProcess(AmpInstance i) {
    starts++;
    return _change(true);
  }

  @override
  Future<void> stopInstanceProcess(AmpInstance i) {
    stops++;
    return _change(false);
  }
}

class _Model extends AppModel {
  _Model(this.api) : super(SettingsStore());

  final AmpClient api;

  @override
  AmpClient get clientOrNull => api;

  @override
  AmpClient get client => api;
}

void main() {
  late _Client client;

  setUp(() => client = _Client());
  tearDown(() => client.close());

  Future<void> showScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppModel>(
        create: (_) => _Model(client),
        child: const MaterialApp(home: InstancesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder toggle() => find.byType(OutlinedButton);

  testWidgets('instance controls fit a narrow mobile display', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    client.running = true;
    client.friendlyName = 'Minecraft Survival mit einem langen Instanznamen';
    await showScreen(tester);
    expect(find.text('Instanz stoppen'), findsOneWidget);
    expect(find.text('Server verwalten'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starts an offline instance directly and separates status', (
    tester,
  ) async {
    await showScreen(tester);
    expect(find.text('AMP-Instanz: Gestoppt'), findsOneWidget);
    await tester.tap(find.text('Instanz starten'));
    await tester.pumpAndSettle();
    expect(client.starts, 1);
    expect(find.text('AMP-Instanz: Läuft'), findsOneWidget);
    expect(find.text('Server: '), findsOneWidget);
    expect(find.text('Gestoppt'), findsOneWidget);
    expect(find.text('Server verwalten'), findsOneWidget);
  });

  testWidgets('stop requires confirmation and can be cancelled', (
    tester,
  ) async {
    client.running = true;
    await showScreen(tester);
    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(find.textContaining('Ein laufender Server'), findsOneWidget);
    expect(client.stops, 0);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(client.stops, 0);
    expect(tester.widget<OutlinedButton>(toggle()).onPressed, isNotNull);

    await tester.tap(toggle());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Instanz stoppen'));
    await tester.pumpAndSettle();
    expect(client.stops, 1);
    expect(find.text('AMP-Instanz: Gestoppt'), findsOneWidget);
    expect(find.text('Server verwalten'), findsNothing);
    expect(find.text('Instanz starten'), findsOneWidget);
  });

  testWidgets('locks actions until ADS confirms the process state', (
    tester,
  ) async {
    client.updateImmediately = false;
    await showScreen(tester);
    await tester.tap(toggle());
    await tester.pump();
    expect(find.text('Instanz startet …'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(toggle()).onPressed, isNull);
    await tester.tap(find.text('Survival'));
    await tester.pump();
    expect(client.starts, 1);
    expect(find.byType(AlertDialog), findsNothing);
    client.running = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('AMP-Instanz: Läuft'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(toggle()).onPressed, isNotNull);
  });

  testWidgets('reports failures and allows another attempt', (tester) async {
    client.actionError = 'Keine Berechtigung';
    await showScreen(tester);
    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(find.text('Keine Berechtigung'), findsOneWidget);
    expect(find.text('AMP-Instanz: Gestoppt'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(toggle()).onPressed, isNotNull);
    client.actionError = null;
    await tester.tap(toggle());
    await tester.pumpAndSettle();
    expect(client.starts, 2);
    expect(find.text('AMP-Instanz: Läuft'), findsOneWidget);
  });

  testWidgets('times out without falsely reporting a running instance', (
    tester,
  ) async {
    client.updateImmediately = false;
    await showScreen(tester);
    await tester.tap(toggle());
    await tester.pump();
    for (var n = 0; n < 15; n++) {
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('noch nicht bestätigt'), findsOneWidget);
    expect(find.text('AMP-Instanz: Gestoppt'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(toggle()).onPressed, isNotNull);
    expect(client.starts, 1);
  });

  testWidgets('does not update a disposed screen after an action completes', (
    tester,
  ) async {
    client.actionGate = Completer<void>();
    await showScreen(tester);
    await tester.tap(toggle());
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    client.actionGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an offline instance still offers to start it', (
    tester,
  ) async {
    await showScreen(tester);
    await tester.tap(find.text('Survival'));
    await tester.pumpAndSettle();
    expect(find.text('Instanz starten?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Instanz starten'));
    await tester.pumpAndSettle();
    expect(client.starts, 1);
    expect(find.text('AMP-Instanz: Läuft'), findsOneWidget);
  });
}
