# OpenM

## Kunden-, Projekt- und Produktionsmanagement

OpenM ist eine modulare Management-App für Unternehmen, die Kundenprojekte
von der ersten Anfrage bis zur Umsetzung und Auslieferung organisieren
möchten. Die Anwendung verbindet Kundenverwaltung, Projektplanung,
Dokumentenablage, Aufgaben, Beschaffung und Produktion in einer gemeinsamen
Oberfläche.

Dieses Repository enthält das Flutter-Frontend (`OpenM_frontend_flutter/`) und
das Python-Backend (`OpenM_backend_python/`). Die REST-API wird separat
gestartet.

> **Hinweis:** OpenM befindet sich in aktiver Entwicklung. Einige Bereiche,
> insbesondere Produktionskennzahlen, Zeiterfassung und die
> Dashboard-Auswertungen, werden laufend erweitert.

## Ziele der App

OpenM soll wiederkehrende Abläufe in der Projekt- und Auftragsbearbeitung
vereinfachen und Informationen an einem zentralen Ort verfügbar machen.
Die wichtigsten Ziele sind:

- **Durchgängige Projektübersicht:** Der Status eines Projekts soll von der
  Anfrage über Bestellung und Konstruktion bis zur Montage und Abnahme
  nachvollziehbar sein.
- **Weniger Medienbrüche:** Kunden, Ansprechpartner, Dateien, Aufgaben,
  Bestellungen und Notizen werden direkt am jeweiligen Unternehmen oder
  Projekt verwaltet.
- **Transparente Planung:** Gantt-Phasen, Unteraufgaben, Zuständigkeiten und
  Projektaktionen helfen bei der zeitlichen und organisatorischen Planung.
- **Bessere Produktionssteuerung:** Beschaffungsstatus, Lieferungen,
  überfällige Teile und geplante Arbeitszeiten sollen frühzeitig sichtbar
  werden.
- **Individuelle Arbeitsoberflächen:** Mitarbeitende können ihr
  Management-Dashboard aus passenden Widgets zusammenstellen.
- **Erweiterbare Grundlage:** Neue Workflows, Aktionen, Dashboard-Widgets,
  Dokumenttypen und Integrationen sollen ohne grundlegenden Umbau der App
  ergänzt werden können.

## Funktionsumfang

### Kunden und Unternehmen

- Verwaltung von Haupt- und Kundenunternehmen
- Ansprechpartner und Kontaktdaten
- Projektübersicht je Unternehmen
- Suche und Auswahl von Unternehmen

### Projekte und Aufträge

- Projektanlage und Projektübersicht
- Status- und Workflow-Fortschritt
- Angebotsnotizen und Angebotsdokumente
- Auftrags- und Bestellpositionen
- Teileauswahl und Beschaffungsstatus
- Liefernummern, Liefertermine und Statusnotizen
- Projektbezogene Aktionen und Notizen

### Planung und Produktion

- Gantt-Phasen und Unterphasen
- Vorlagen für neue Projekt-Gantt-Pläne
- Zuständigkeiten für Unteraufgaben
- Fortschrittsanzeige und aktuelle Projektphase
- Dashboard für die Zeit von der Bestellung bis zum Baubeginn
- Dashboard für geplante Projektarbeitsstunden
- Übersicht über bestellte, unterwegs befindliche, überfällige und
  gelieferte Teile

Die Arbeitsstunden im aktuellen Dashboard werden aus den geplanten Gantt-
Arbeitstagen berechnet. Dabei wird ein Arbeitstag mit acht Stunden angesetzt.
Eine echte Mitarbeiter-Zeiterfassung ist als Erweiterung vorgesehen und
stellt keine Voraussetzung für die vorhandene Projektplanung dar.

### Dokumente und Dateien

- Projektbezogene Ordnerstrukturen
- Dateiablage und Dateiverwaltung
- Vorlagen für Projektordner
- Erstellung und Download projektbezogener Dokumente
- Unterstützung für PDF-, Excel-, Word- und PowerPoint-Dokumente über das
  Backend

### Aufgaben, Kalender und Workflows

- To-dos für Unternehmen und Projekte
- Fälligkeiten, Zuständigkeiten und Delegation
- Kalender- und Kanban-Ansichten
- Workflow-Definitionen und Workflow-Editor
- Administrierbare Projektaktionen und Workflow-Knoten

### Management-Dashboard

Das Management-Dashboard ist pro Mitarbeitendem konfigurierbar. Über die
Dashboard-Auswahl können Widgets ein- und ausgeblendet werden. Zurzeit
stehen unter anderem folgende Widgets zur Verfügung:

- Übersicht und Kennzahlen
- Statistiken
- Neue Kundenunternehmen
- Shipping Pipeline
- Order-to-Build-Zeit
- Geplante Projektarbeitsstunden

Weitere Widgets können im
[`dashboard_widget_catalog.dart`](lib/screens/management_dashboard/dashboard_widget_catalog.dart)
registriert werden.

### Administration

- Mitarbeitende und Rollen
- Abteilungen
- Teile und Hersteller
- Gantt-Vorlagen
- Projektaktionen und Workflows
- Servereinstellungen für E-Mail und KI-Dienste

## Architektur

OpenM besteht aus zwei getrennten Komponenten:

```text
┌─────────────────────────────┐
│ Flutter-App                 │
│ Flutter-Frontend            │
│                             │
│ Screens, Router, Widgets,   │
│ Riverpod-State, API-Client  │
└──────────────┬──────────────┘
               │ REST / JSON
               │ Bearer-Token
┌──────────────▼──────────────┐
│ FastAPI-Backend             │
│ FastAPI-Backend             │
│                             │
│ Auth, Projekte, Firmen,     │
│ Dateien, Aufgaben, Teile,   │
│ Workflows und Datenbank     │
└─────────────────────────────┘
```

### Frontend-Technologien

- [Flutter](https://flutter.dev/)
- Dart `^3.11.5`
- [Riverpod](https://riverpod.dev/) für Zustände und Provider
- [GoRouter](https://pub.dev/packages/go_router) für Navigation
- [Dio](https://pub.dev/packages/dio) für HTTP-Kommunikation
- `fl_chart` für Diagramme
- `shared_preferences` für lokale Dashboard-Auswahl und Sitzungsdaten
- Deutsche und englische Benutzeroberfläche

### Backend-Technologien

- Python
- [FastAPI](https://fastapi.tiangolo.com/)
- SQLAlchemy
- Pydantic
- SQLite als lokale Standarddatenbank
- JWT-basierte Authentifizierung

## Voraussetzungen

- Flutter SDK mit Unterstützung für Dart `3.11.5` oder höher im Bereich der
  unterstützten Versionen
- Python 3.10 oder höher
- Git
- Ein laufendes OpenM-Backend

Die unterstützten Zielplattformen werden durch die vorhandenen Flutter-
Projektordner bestimmt, unter anderem Windows, Android, iOS, macOS und Web.

## Installation und Start

### 1. Repository klonen

```powershell
git clone <REPOSITORY-URL>
Set-Location OpenM
```

### 2. Backend einrichten

```powershell
$backend = Get-ChildItem -Directory *backend* | Select-Object -First 1
Set-Location $backend.FullName
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn app.main:app --reload --port 8002
```

Die API ist danach standardmäßig unter
`http://127.0.0.1:8002` erreichbar. Der Backend-Start legt die SQLite-
Datenbank bei Bedarf im Datenbankverzeichnis des Backend-Projekts an.
Falls dort noch eine ältere `bfsa.db` liegt und `openm.db` noch nicht
existiert, übernimmt OpenM die Daten in eine neue `openm.db`. Die alte
Datei bleibt erhalten; das alte Admin-Konto wird bis zur Vergabe eines
neuen Passworts gesperrt.

Für JWT-Anmeldetokens verwendet das Backend `OPENM_SECRET_KEY`, wenn die
Variable mit mindestens 32 Zeichen gesetzt ist. Andernfalls erzeugt OpenM
ein zufälliges Signaturgeheimnis in `database/.openm_jwt_secret`. Datenbank
und Schlüsseldatei sind lokale Laufzeitdateien und gehören nicht ins Git-
Repository.

Für eine zentrale Dateiablage kann vor dem Start des Backends ein eigener
Speicherort gesetzt werden:

```powershell
$env:OPENM_STORAGE_ROOT = "D:\OpenM-Files"
uvicorn app.main:app --reload --port 8002
```

Gesundheitsstatus und interaktive API-Dokumentation sind unter folgenden
Adressen verfügbar:

- `http://127.0.0.1:8002/health`
- `http://127.0.0.1:8002/docs`

### 3. Frontend einrichten

In einem zweiten Terminal:

```powershell
$frontend = Get-ChildItem -Directory *frontend* | Select-Object -First 1
Set-Location $frontend.FullName
flutter pub get
flutter run
```

Die lokale Standardkonfiguration des Frontends erwartet das Backend unter
`http://127.0.0.1:8002`. Diese Werte können in
[`backend_settings.dart`](lib/core/backend_settings.dart) angepasst werden:

```dart
static const String protocol = 'http';
static const String host = '127.0.0.1';
static const int port = 8002;
```

Bei einem Android-Emulator muss `127.0.0.1` in der Regel durch
`10.0.2.2` ersetzt werden. Bei einem physischen Gerät muss die IP-Adresse
des Entwicklungsrechners verwendet werden. Das Gerät und der Rechner
müssen sich im selben Netzwerk befinden.

### 4. Administrator initial einrichten

Beim ersten Start zeigt die App automatisch die einmalige
Administratoreinrichtung an, wenn die Datenbank leer ist oder ein
migriertes altes Admin-Konto noch kein neues Passwort erhalten hat. In
einer leeren Datenbank werden Organisation, Name, E-Mail, Login-Name und
ein mindestens 12 Zeichen langes Administratorpasswort festgelegt. Bei
einer Migration bleiben Organisation und Projektdaten erhalten; das
bisherige Admin-Konto wird mit den neu eingegebenen Kontodaten gesichert.
Nach erfolgreicher Einrichtung wird die Sitzung gestartet.

Es gibt kein voreingestelltes Admin-Passwort. Die Einrichtung ist danach
gesperrt. Alte lokal gespeicherte Sitzungen werden bei der Umstellung
verworfen. Der separate Demo-Reset fragt das Admin-Passwort ebenfalls
interaktiv ab und setzt zufällige Passwörter für die übrigen Demo-Konten.

## Entwicklung

### Code analysieren

```powershell
$frontend = Get-ChildItem -Directory *frontend* | Select-Object -First 1
Set-Location $frontend.FullName
flutter analyze
```

### Tests ausführen

```powershell
flutter test
```

### Frontend formatieren

```powershell
dart format lib test
```

### Backend-Tests ausführen

```powershell
$backend = Get-ChildItem -Directory *backend* | Select-Object -First 1
Set-Location $backend.FullName
python -m pytest
```

## Projektstruktur

```text
OpenM/
├── <frontend-verzeichnis>/
│   ├── lib/
│   │   ├── core/                 # Routing, Theme, Lokalisierung, Konfiguration
│   │   ├── models/               # DTOs und Statusmodelle
│   │   ├── providers/            # Zustandsprovider
│   │   ├── screens/              # App-Seiten und Dashboard
│   │   ├── services/             # API-Client und Authentifizierung
│   │   └── widgets/              # Wiederverwendbare UI-Komponenten
│   ├── android/
│   ├── ios/
│   ├── macos/
│   ├── web/
│   ├── windows/
│   ├── pubspec.yaml
│   └── README.md
└── <backend-verzeichnis>/
    ├── app/
    │   ├── routers/              # REST-Endpunkte
    │   ├── models.py             # SQLAlchemy-Modelle
    │   ├── schemas.py            # API-Schemas
    │   └── main.py
    ├── tests/
    ├── requirements.txt
    └── database/
```

## Sicherheit und Konfiguration

- Zugangsdaten und Tokens gehören nicht in das Repository.
- Produktive Installationen sollten HTTPS verwenden.
- Die offene CORS-Konfiguration des lokalen Backends muss für den
  Produktivbetrieb eingeschränkt werden.
- Datenbank- und Dateiablagen sollten regelmäßig gesichert werden.
- Server- und KI-Zugangsdaten sollten ausschließlich über geschützte
  Konfiguration beziehungsweise Umgebungsvariablen verwaltet werden.

## Geplante Erweiterungen

Die Architektur ist auf folgende Erweiterungen vorbereitet:

- echte Arbeitszeiterfassung pro Mitarbeitendem und Projekt
- detailliertere Produktions- und Versandkennzahlen
- Auswertungen von Auftrag bis Fertigstellung
- zusätzliche Rollen- und Rechteverwaltung
- weitere externe Integrationen
- erweiterte Benachrichtigungen und automatische Workflows

## Lizenz

Für dieses Projekt ist in diesem Repository derzeit keine Lizenzdatei
hinterlegt. Eine Nutzung, Weitergabe oder Veröffentlichung sollte daher vorab
mit den Projektverantwortlichen abgestimmt werden.
