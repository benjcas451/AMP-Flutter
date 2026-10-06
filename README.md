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

## CI & TestFlight (GitHub Actions)

- **CI** (`.github/workflows/ci.yml`): `flutter analyze` und `flutter test` auf macOS bei jedem
  Pull Request und Push auf `main`.
- **TestFlight** (`.github/workflows/testflight.yml`): baut ein signiertes IPA und lädt es zu
  App Store Connect hoch – automatisch bei jedem Push auf `main`, manuell für beliebige Branches
  über *Actions → TestFlight → Run workflow*. Zertifikat und Provisioning-Profil holt der Workflow
  selbst über die App Store Connect API ([Codemagic CLI tools](https://github.com/codemagic-ci-cd/cli-tools)),
  die Build-Nummer ist immer die zuletzt hochgeladene + 1.

Einmalige Einrichtung:

1. In App Store Connect unter *Benutzer und Zugriff → Integrationen → App Store Connect API*
   einen Team-Schlüssel mit der Rolle **App Manager** anlegen. `.p8`-Datei herunterladen,
   Key-ID und Issuer-ID notieren.
2. Einen privaten Schlüssel für das Distributions-Zertifikat erzeugen und gut aufbewahren
   (derselbe Schlüssel sorgt dafür, dass das Zertifikat wiederverwendet wird):
   ```bash
   ssh-keygen -t rsa -b 2048 -m PEM -f cert_key -q -N ""
   ```
3. Im GitHub-Repo unter *Settings → Secrets and variables → Actions* anlegen:

   | Secret | Inhalt |
   | --- | --- |
   | `APP_STORE_CONNECT_ISSUER_ID` | Issuer-ID |
   | `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key-ID |
   | `APP_STORE_CONNECT_PRIVATE_KEY` | kompletter Inhalt der `AuthKey_<KEY_ID>.p8` |
   | `CERTIFICATE_PRIVATE_KEY` | kompletter Inhalt von `cert_key` |

Hinweise: Beim ersten Lauf legt der Workflow ein neues *Apple Distribution*-Zertifikat an,
falls keines zum Schlüssel passt – Apple erlaubt nur wenige davon pro Team. Die `version` in
`pubspec.yaml` muss höher sein als die zuletzt im App Store veröffentlichte Version.

## Hinweise

- HTTP ist erlaubt (`usesCleartextTraffic` / `NSAllowsArbitraryLoads`), damit das Panel im LAN
  funktioniert. Für Zugriff von unterwegs HTTPS (Reverse Proxy) oder ein VPN verwenden.
- Für die App am besten einen eigenen AMP-Benutzer mit passenden Rechten anlegen.
