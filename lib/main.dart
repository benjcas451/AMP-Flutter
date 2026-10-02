import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/instances_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_store.dart';
import 'state/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppModel(SettingsStore())..init(),
      child: const AmpApp(),
    ),
  );
}

class AmpApp extends StatelessWidget {
  const AmpApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7D32);
    return MaterialApp(
      title: 'AMP Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    if (!model.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!model.isConfigured) {
      return const SettingsScreen(firstRun: true);
    }
    return const InstancesScreen();
  }
}
