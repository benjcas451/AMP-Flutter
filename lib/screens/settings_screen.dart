import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/amp_client.dart';
import '../services/settings_store.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.firstRun = false});

  /// Shown as start screen when nothing is configured yet.
  final bool firstRun;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _url;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppModel>().settings;
    _url = TextEditingController(text: s.url);
    _user = TextEditingController(text: s.username);
    _pass = TextEditingController(text: s.password);
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  ServerSettings get _current => ServerSettings(
    url: _url.text,
    username: _user.text,
    password: _pass.text,
  );

  void _snack(String msg, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? cs.error : null),
    );
  }

  /// Tries to log in with the entered values. Returns true on success.
  Future<bool> _test({bool quiet = false}) async {
    if (!_formKey.currentState!.validate()) return false;
    setState(() => _busy = true);
    final s = _current;
    final client = AmpClient(
      baseUrl: s.url,
      username: s.username,
      password: s.password,
    );
    try {
      final app = await client.testConnection();
      await client.logout();
      if (mounted && !quiet) _snack('Verbindung erfolgreich ($app).');
      return true;
    } on AmpException catch (e) {
      if (mounted) _snack(e.message, error: true);
      return false;
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!await _test(quiet: true)) return;
    if (!mounted) return;
    await context.read<AppModel>().saveSettings(_current);
    if (!mounted) return;
    _snack('Einstellungen gespeichert.');
    if (!widget.firstRun) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zugangsdaten löschen?'),
        content: const Text(
          'Server-URL, Benutzer und Passwort werden von diesem Gerät entfernt.',
        ),
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
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    await context.read<AppModel>().clearSettings();
    // Back to the root, which now shows the first-run settings screen.
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final configured = context.watch<AppModel>().isConfigured;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.firstRun ? 'AMP Control einrichten' : 'Einstellungen',
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.firstRun)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Gib die Adresse deines AMP-Panels und deine Zugangsdaten '
                    'ein. Die Daten werden verschlüsselt auf dem Gerät gespeichert.',
                  ),
                ),
              TextFormField(
                controller: _url,
                decoration: const InputDecoration(
                  labelText: 'Server-URL',
                  hintText:
                      'https://amp.example.com oder http://192.168.1.10:8080',
                  prefixIcon: Icon(Icons.dns_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final u = AmpClient.normalizeUrl(v ?? '');
                  if (u.isEmpty) return 'Bitte Server-URL eingeben';
                  final parsed = Uri.tryParse(u);
                  if (parsed == null || parsed.host.isEmpty) {
                    return 'Ungültige URL';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _user,
                decoration: const InputDecoration(
                  labelText: 'Benutzer',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                autocorrect: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Bitte Benutzer eingeben' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pass,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Anzeigen' : 'Verbergen',
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _save(),
                validator: (v) =>
                    (v ?? '').isEmpty ? 'Bitte Passwort eingeben' : null,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _test(),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Testen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Speichern'),
                    ),
                  ),
                ],
              ),
              if (configured && !widget.firstRun) ...[
                const SizedBox(height: 32),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Zugangsdaten löschen'),
                  onTap: _busy ? null : _clear,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Tipp: Lege in AMP einen eigenen Benutzer für die App an und '
                'nutze für den Zugriff von unterwegs HTTPS oder ein VPN.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
