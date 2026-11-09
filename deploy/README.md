# OpenM mit Docker betreiben

OpenM besteht aus einem Flutter-Webfrontend, nginx als Webserver und
Reverse-Proxy sowie einem FastAPI-Backend mit SQLite. Docker Compose startet
Frontend und Backend gemeinsam. nginx leitet Anfragen unter `/api/` an das
Backend weiter; das Backend muss nicht separat veröffentlicht werden.

## Variante A: Direkt aus dem GitHub-Quellcode

Voraussetzung ist Docker mit Compose und laufender Docker Engine. Die folgenden
Befehle werden im Repository-Hauptverzeichnis ausgeführt:

```shell
docker compose -f deploy/docker-compose.source.yml up -d --build
docker compose -f deploy/docker-compose.source.yml ps
docker compose -f deploy/docker-compose.source.yml logs -f
```

Der erste Build lädt das Flutter-Image und die Python-Abhängigkeiten herunter.
Das Frontend wird im Container mit `API_BASE_URL=/api` gebaut und anschließend
von nginx ausgeliefert. Öffne `http://localhost` beziehungsweise
`http://<server>`. Für die Konfiguration kann `deploy/.env.example` nach
`deploy/.env` kopiert werden; Compose lädt diese Datei bei dieser Variante
automatisch. Die persistenten Daten liegen unter `deploy/data/`.

Zum Aktualisieren den neuen Quellcode bereitstellen und `up -d --build` erneut
ausführen. `deploy/data/` und `deploy/.env` dabei beibehalten.

## Variante B: Vorgebautes Serverpaket

Für diese Variante werden Flutter und Docker Compose benötigt: Flutter auf dem
Build-Rechner, Docker und Compose auf dem Zielserver. Unter Windows im
Repository-Hauptverzeichnis:

```powershell
.\build_server.bat
```

Das Skript erstellt `dist\openm-server` mit dem bereits gebauten Webfrontend,
dem Backend-Quellcode und der Compose-Konfiguration. Falls das Ziel bereits
existiert, bricht das Skript ab und löscht oder überschreibt nichts. Für einen
weiteren Build ein **neues** Verzeichnis angeben:

```powershell
.\build_server.bat dist\openm-server-neu
```

Den Inhalt des neuen Pakets auf den Server kopieren. Dort im Paketverzeichnis:

```shell
docker compose up -d --build
docker compose ps
docker compose logs -f
```

Optional `.env.example` nach `.env` kopieren. Die persistenten Daten liegen
bei dieser Variante im Paketverzeichnis unter `data/`. Beim Update bestehende
`data/`- und `.env`-Dateien nicht durch Inhalte des neuen Pakets ersetzen;
stattdessen die neuen Programmdateien bereitstellen und Compose erneut bauen.

## Einrichtung und Konfiguration

Beim ersten Start wird in der App ein Super-Administrator angelegt; es gibt
keine voreingestellten Zugangsdaten. Das Konto verwaltet Organisationen.

| Variable | Standard | Bedeutung |
|---|---|---|
| `OPENM_PORT` | `80` | Host-Port für die Weboberfläche |
| `OPENM_SECRET_KEY` | leer | Optionaler JWT-Signaturschlüssel, mindestens 32 Zeichen |

Ohne `OPENM_SECRET_KEY` erzeugt das Backend einen Schlüssel in
`data/database/`. Bei einem gesetzten Schlüssel muss derselbe Wert bei jedem
Start erhalten bleiben. `.env` und Schlüssel nicht veröffentlichen.

`data/database/` enthält SQLite-Datenbank und gegebenenfalls den automatisch
erzeugten Schlüssel; `data/storage/` enthält hochgeladene Dokumente. Beide
Verzeichnisse regelmäßig gemeinsam sichern. Für ein konsistentes Backup
Compose zuerst mit `docker compose ... stop` anhalten, die Daten kopieren und
anschließend mit `docker compose ... start` wieder starten. Bei Variante A
jeweils `-f deploy/docker-compose.source.yml` ergänzen.

**Sicherheit:** Die Beispielkonfiguration stellt HTTP bereit. Vor einer
Veröffentlichung im Internet ist ein TLS-terminierender Reverse-Proxy nötig.
Die optionale KI-Chat-Crew und LM Studio sind in den Docker-Images nicht
enthalten; der Chat erfordert eine separate Einrichtung.
