# OpenM mit Docker betreiben

OpenM besteht aus einem Flutter-Webfrontend, nginx als Webserver und
Reverse-Proxy, einem FastAPI-Backend und einer PostgreSQL-Datenbank. Docker
Compose startet alle Komponenten gemeinsam. nginx leitet Anfragen unter
`/api/` an das Backend weiter; das Backend muss nicht separat veröffentlicht
werden.

## Variante A: Direkt aus dem GitHub-Quellcode

Voraussetzung ist Docker mit Compose und laufender Docker Engine. Die folgenden
Befehle werden im Repository-Hauptverzeichnis ausgeführt:

```shell
Copy-Item deploy\.env.example deploy\.env
# Setze OPENM_DB_PASSWORD in deploy\.env auf ein eigenes Passwort.
docker compose --env-file deploy\.env -f deploy/docker-compose.source.yml up -d --build
docker compose --env-file deploy\.env -f deploy/docker-compose.source.yml ps
docker compose --env-file deploy\.env -f deploy/docker-compose.source.yml logs -f
```

Der erste Build lädt das Flutter-Image und die Python-Abhängigkeiten herunter.
Das Frontend wird im Container mit `API_BASE_URL=/api` gebaut und anschließend
von nginx ausgeliefert. Öffne `http://localhost` beziehungsweise
`http://<server>`. Setze vor dem Start `OPENM_DB_PASSWORD` in `deploy/.env`.
PostgreSQL speichert seine Daten in einem Docker-Volume. Uploads und ein
automatisch erzeugter JWT-Schlüssel liegen unter `deploy/data/`. Bestehende
SQLite-Daten werden nicht übernommen.

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
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
docker compose --env-file .env logs -f
```

`.env.example` nach `.env` kopieren und `OPENM_DB_PASSWORD` setzen. Die
persistent gespeicherten Dateien liegen bei dieser Variante im Paketverzeichnis
unter `data/`. Beim Update bestehende
`data/`- und `.env`-Dateien nicht durch Inhalte des neuen Pakets ersetzen;
stattdessen die neuen Programmdateien bereitstellen und Compose erneut bauen.

## Einrichtung und Konfiguration

Beim ersten Start wird in der App ein Super-Administrator angelegt; es gibt
keine voreingestellten Zugangsdaten. Das Konto verwaltet Organisationen.

| Variable | Standard | Bedeutung |
|---|---|---|
| `OPENM_PORT` | `80` | Host-Port für die Weboberfläche |
| `OPENM_DB_NAME` | `openm` | PostgreSQL-Datenbank |
| `OPENM_DB_USER` | `openm` | PostgreSQL-Benutzer |
| `OPENM_DB_PASSWORD` | erforderlich | PostgreSQL-Passwort |
| `OPENM_SECRET_KEY` | leer | Optionaler JWT-Signaturschlüssel, mindestens 32 Zeichen |

Ohne `OPENM_SECRET_KEY` erzeugt das Backend einen Schlüssel in
`data/state/`. Bei einem gesetzten Schlüssel muss derselbe Wert bei jedem
Start erhalten bleiben. `.env` und Schlüssel nicht veröffentlichen.

Das Docker-Volume `postgres_data` enthält die PostgreSQL-Datenbank;
`data/storage/` enthält hochgeladene Dokumente und `data/state/` den
gegebenenfalls automatisch erzeugten Schlüssel. Alle drei Datenbestände
regelmäßig gemeinsam sichern. SQLite-Daten werden beim Umstieg nicht
migriert.

**Sicherheit:** Die Beispielkonfiguration stellt HTTP bereit. Vor einer
Veröffentlichung im Internet ist ein TLS-terminierender Reverse-Proxy nötig.
Die optionale KI-Chat-Crew und LM Studio sind in den Docker-Images nicht
enthalten; der Chat erfordert eine separate Einrichtung.
