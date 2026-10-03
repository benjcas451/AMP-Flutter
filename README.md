# AMP Control

Flutter-App (Android & iOS) zur Steuerung eines CubeCoders-AMP-Panels über dessen JSON-API.

## Funktionen

- **Einstellungen**: Server-URL, Benutzer, Passwort – mit Verbindungstest, sicher gespeichert
  (Android Keystore / iOS Keychain)
- **Instanzliste**: alle Instanzen des ADS mit Status, CPU/RAM/Spielern, Auto-Refresh
  - AMP-Instanzen direkt starten / stoppen, mit getrenntem Instanz- und Serverstatus
  - Bestätigung vor dem Instanzstopp; Aktionen bleiben bis zur Statusbestätigung gesperrt
- **Instanz-Details**
  - Übersicht: Serverstatus, Metriken, Server starten / stoppen / neustarten / Kill
  - Konsole: Live-Ausgabe, Befehle senden
  - Spieler: aktuell verbundene Benutzer

## Aufbau

```
lib/
  api/amp_client.dart      HTTP-Client, Login, Session-Handling, ADS-Proxy
  api/models.dart          Instanzen, Status, Metriken, Konsolenzeilen
  services/settings_store.dart  sichere Speicherung der Zugangsdaten
  state/app_state.dart     App-Zustand (provider)
  screens/                 Einstellungen, Instanzliste, Instanz-Details
```

Instanzen werden über den ADS-Proxy angesprochen (`/API/ADSModule/Servers/<id>/API/...`),
die App braucht daher nur die URL des ADS (z. B. `http://192.168.1.10:8080`).
Die AMP-Instanzen selbst werden über `ADSModule/StartInstance` und
`ADSModule/StopInstance` gesteuert. Beim Stoppen einer Instanz wird auch ein darin
laufender Server beendet; der ADS-Controller selbst wird nicht in der Liste angezeigt.

## Bauen

```bash
flutter pub get
flutter run                  # auf angeschlossenem Gerät/Emulator
flutter build apk --release  # Android
flutter build ipa            # iOS (macOS + Xcode erforderlich)
flutter test
```

Bundle-ID: iOS `de.tschapps.ampControl`, Android `de.tschapps.amp_control`.

## Hinweise

- HTTP ist erlaubt (`usesCleartextTraffic` / `NSAllowsArbitraryLoads`), damit das Panel im LAN
  funktioniert. Für Zugriff von unterwegs HTTPS (Reverse Proxy) oder ein VPN verwenden.
- Für die App am besten einen eigenen AMP-Benutzer mit passenden Rechten anlegen.
