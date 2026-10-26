# OpenM server deployment

Requires Docker with Compose on the server.

1. Copy this whole folder to the server.
2. (Optional) copy `.env.example` to `.env` and adjust `OPENM_PORT` / `OPENM_SECRET_KEY`.
3. Start: `docker compose up -d --build`
4. Open `http://<server>:<OPENM_PORT>` and complete the first-run setup. The
   account created there is the super admin who can add organizations.

Data lives in `./data` (`database/` = SQLite DB and JWT key, `storage/` = uploaded files).
Back up this folder. Updating: replace `backend/` and `web/` with a new build, then
`docker compose up -d --build`; `data/` is kept.

The app is served over HTTP. Put it behind a TLS-terminating reverse proxy
(or add certificates to `nginx.conf`) before exposing it to the internet.
