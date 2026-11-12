# OpenM

Kunden-, Projekt- und Produktionsmanagement: Kundenverwaltung, Projektplanung
(Gantt), Dokumentenablage, Aufgaben, Beschaffung und Produktion in einer
gemeinsamen Oberfläche. Mehrere Organisationen (Mandanten) werden von einem
Super-Admin verwaltet.

> OpenM befindet sich in aktiver Entwicklung.

## Einblicke in die Anwendung

Die folgenden Aufnahmen zeigen die echte Oberfläche mit **fiktiven
Beispieldaten**. Es werden keine Kundendaten aus einer laufenden Instanz
verwendet.

### Kundenunternehmen und Aufgaben

![Kundenunternehmen mit Aufgaben](OpenM_frontend_flutter/screenshots/customer-companies.png)

### Projektübersicht und Fortschritt

![Projektübersicht mit Workflow-Status](OpenM_frontend_flutter/screenshots/project-overview.png)

### Management-Dashboard

![Management-Dashboard mit Kennzahlen](OpenM_frontend_flutter/screenshots/management-dashboard.png)

## Funktionen

- Kundenunternehmen, Ansprechpartner und projektbezogene Dokumente verwalten.
- Projekte vom Angebot bis zur Abnahme verfolgen und ihren Fortschritt anzeigen.
- Angebote als PDF erzeugen, die Angebotsliste öffnen und ausgewählte Angebote
  an Kundenkontakte senden.
- Aufgaben, Kalender, Gantt-Planung, Beschaffung und Produktion unterstützen.
- Mitarbeitende, Rollen, Vorlagen und Workflows zentral administrieren.

Einige Funktionen, insbesondere Produktionskennzahlen und Zeiterfassung,
befinden sich noch in Entwicklung. Das Dashboard enthält teilweise
Beispielkennzahlen.

## Projekt auf GitHub veröffentlichen

Der Projektordner enthält den vollständigen Quellcode und kann in ein anderes
Verzeichnis kopiert werden. Lokale Daten, Passwörter, virtuelle Umgebungen
und Build-Dateien gehören nicht in das Repository. Für ein neues, leeres
GitHub-Repository im kopierten Ordner:

```powershell
git init
git branch -M main
git add .
git commit -m "Initial OpenM version"
git remote add origin <GITHUB-REPOSITORY-URL>
git push -u origin main
```

`.gitignore` schließt unter anderem `.env`, Datenbanken, Uploads und
Signaturschlüssel aus.

### GitHub-Ordner prüfen und Docker-Images bauen

Unter Windows prüft die Batchdatei im ursprünglichen OpenM-Quellordner die
Frontend-, Backend- und Deployment-Dateien gegen diesen Ordner. Dafür werden
Git und für den Docker-Build eine laufende Docker Engine mit Compose benötigt.

```powershell
cd D:\Projekte\OpenM
.\deploy_openm.bat check
.\deploy_openm.bat sync
.\deploy_openm.bat build
```

`check` meldet Unterschiede ohne Änderungen. `sync` kopiert abweichende
Quelldateien. `build` synchronisiert und baut danach die Docker-Images, ohne
Container zu starten. Für den Build wird bei fehlendem `OPENM_DB_PASSWORD`
ein temporärer Platzhalter verwendet, nicht für den Betrieb. Zusätzliche Quelldateien im Ziel werden gemeldet, aber
nicht gelöscht. Lokale Daten, `.env`, Uploads und Build-Caches bleiben
unverändert. GitHub-Commits werden nicht automatisch heruntergeladen.

## Inhalt

| Ordner | Beschreibung |
|---|---|
| [`OpenM_backend_python/`](OpenM_backend_python) | FastAPI-Backend mit PostgreSQL |
| [`OpenM_frontend_flutter/`](OpenM_frontend_flutter) | Flutter-App (Web/Desktop) – ausführliche Doku in der [README](OpenM_frontend_flutter/README.md) |
| [`deploy/`](deploy) | Docker-Builds, Compose und nginx für den Serverbetrieb |
| `start_openm.bat` | Startet Backend und Frontend lokal (Windows) |
| `build_server.bat` | Erstellt das Serverpaket `dist/openm-server` |

## Voraussetzungen

- Python 3.13+
- Flutter SDK (Web aktiviert)
- PostgreSQL 17 oder Docker mit Compose
- Optional: [`uv`](https://docs.astral.sh/uv/) und LM Studio für den KI-Chat-Assistenten
- Für den Serverbetrieb: Docker mit Compose

## Lokal starten (Windows)

```powershell
Copy-Item deploy\.env.example deploy\.env
# OPENM_DB_PASSWORD in deploy\.env auf ein eigenes Passwort setzen.
docker compose --env-file deploy\.env -f deploy\docker-compose.source.yml up -d database
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r OpenM_backend_python\requirements.txt
.\start_openm.bat
```

Das Backend läuft auf `http://localhost:8002`, das Frontend startet in Chrome.
Das Startskript verwendet ausschließlich die neben ihm liegenden Ordner
`OpenM_backend_python` und `OpenM_frontend_flutter`; fehlen diese, bricht es ab.
`start_openm.bat` prüft vor dem Start die konfigurierte PostgreSQL-Verbindung
einschließlich Anmeldung und Datenbankzugriff. Bei einem Fehler startet es
weder Backend noch Frontend. Die Konfiguration erfolgt über
`OPENM_DATABASE_URL` oder die `OPENM_DB_*`-Umgebungsvariablen. Fehlende
Datenbankvariablen werden aus `deploy/.env` geladen; bereits gesetzte
Umgebungsvariablen haben Vorrang. Der Datenbankcontainer muss zuvor mit dem
oben gezeigten Compose-Befehl gestartet werden.
Ist das Datenbankschema bereits vorhanden, zeigt das Skript zusätzlich an, ob
die Ersteinrichtung abgeschlossen ist. Bei einer neuen Datenbank wird das
Schema erst beim Backendstart erstellt und die Einrichtung in der App geprüft.
Das Frontend startet erst, wenn der Backend-Endpunkt für den Einrichtungsstatus
erreichbar ist. Ist Port 8002 bereits belegt, muss der bestehende Prozess
beendet oder der Port anderweitig freigegeben werden.
Das Datenbankschema wird beim ersten Start angelegt. Bestehende SQLite-Daten
werden nicht automatisch übernommen.

## Erste Einrichtung

Beim ersten Start zeigt die App einen Einrichtungsbildschirm. Das dort
angelegte Konto ist der **Super-Admin**: Er legt die erste Organisation an und
kann weitere Organisationen (optional mit eigenem Administrator) hinzufügen.
Administratoren einer Organisation sehen und verwalten nur ihre eigene
Organisation. Es gibt keine voreingestellten Zugangsdaten. Auch bei einer
gespeicherten Anmeldung prüft OpenM zunächst den Einrichtungsstatus der
aktuellen Datenbank. Ist noch kein Benutzer vorhanden, wird die alte Anmeldung
verworfen und die Einrichtung angezeigt. Ist der Server nicht erreichbar, kann
die Prüfung erneut versucht werden.

## Mit Docker starten

Mit laufender Docker Engine und Compose kann das Repository direkt gebaut
und gestartet werden; ein lokal installiertes Flutter SDK ist dafür nicht
erforderlich:

```shell
docker compose --env-file deploy/.env -f deploy/docker-compose.source.yml up -d --build
docker compose --env-file deploy/.env -f deploy/docker-compose.source.yml ps
```

Die App ist anschließend unter `http://localhost` erreichbar. Der erste Build
kann wegen des Downloads von Flutter und Python-Abhängigkeiten länger dauern.
Vorher `deploy/.env.example` nach `deploy/.env` kopieren und ein eigenes
`OPENM_DB_PASSWORD` setzen; die vorhandene `.env` bei Updates beibehalten.
Im `deploy`-Ordner muss beim Start des Quellprojekts ausdrücklich
`docker compose --env-file .env -f docker-compose.source.yml up -d --build`
verwendet werden: `docker compose up` allein wählt die Konfiguration für das
vorgebaute Serverpaket. PostgreSQL-Daten liegen in einem Docker-Volume;
Uploads und Signaturschlüssel liegen unter `deploy/data/`.
Für den Internetbetrieb ist ein HTTPS-Reverse-Proxy notwendig.

## Vorgebautes Serverpaket

```powershell
.\build_server.bat
```

Den Ordner `dist/openm-server` auf den Server kopieren und dort
`docker compose up -d --build` ausführen. Das Skript überschreibt kein
vorhandenes Ausgabe-Verzeichnis. Für weitere Builds kann ein neuer Zielpfad
angegeben werden, zum Beispiel `.\build_server.bat dist\openm-server-neu`.
Details zu beiden Varianten, Updates, Backups, HTTPS und Einschränkungen stehen
in [`deploy/README.md`](deploy/README.md).

## Tests

```powershell
# Nur eine eigens für Tests eingerichtete PostgreSQL-Datenbank verwenden:
$env:OPENM_TEST_DATABASE_URL = "postgresql+psycopg://user:password@localhost:5432/openm_test"
cd OpenM_backend_python
..\.venv\Scripts\python.exe -m pytest tests\test_initial_setup.py tests\test_super_admin.py

cd ..\OpenM_frontend_flutter
flutter test
```

Die Backendtests erzeugen und löschen isolierte Testschemas in dieser Datenbank;
der angegebene Benutzer benötigt entsprechende Rechte.

## Konfiguration

| Variable | Bedeutung |
|---|---|
| `OPENM_DATABASE_URL` | Optionale SQLAlchemy-PostgreSQL-URL; andernfalls werden die `OPENM_DB_*`-Variablen verwendet. |
| `OPENM_DB_HOST`, `OPENM_DB_PORT`, `OPENM_DB_NAME`, `OPENM_DB_USER`, `OPENM_DB_PASSWORD` | PostgreSQL-Verbindungseinstellungen. |
| `OPENM_SECRET_KEY` | JWT-Signaturschlüssel (mind. 32 Zeichen). Ohne Angabe wird einmalig einer im Zustandsverzeichnis gespeichert. |
| `OPENM_STORAGE_ROOT` | Speicherort für hochgeladene Dateien (siehe [`HOWTO_STORAGE_AND_MIGRATION.md`](OpenM_backend_python/HOWTO_STORAGE_AND_MIGRATION.md)) |
| `API_BASE_URL` | Build-Zeit-Option des Frontends (`--dart-define`), Adresse des Backends |

Datenbanken, Signaturschlüssel und Uploads gehören nicht ins Repository
(siehe `.gitignore`).

## Lizenz

Für dieses Projekt ist derzeit keine Lizenz festgelegt. Vor einer
Veröffentlichung sollte eine passende Lizenzdatei ergänzt werden.
