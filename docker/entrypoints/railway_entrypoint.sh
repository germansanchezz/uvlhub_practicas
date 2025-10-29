#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Creative Commons CC BY 4.0 - David Romero - Diverso Lab
# ---------------------------------------------------------------------------
set -euo pipefail

# 1) Asegura la carpeta de subidas (apunta al volumen /app/uploads)
mkdir -p ./uploads

# 2) (Opcional) Espera a la BD si tienes el script
if [ -x "/app/scripts/wait-for-db.sh" ]; then
  /app/scripts/wait-for-db.sh
fi

# 3) Migraciones Alembic/Flask-Migrate
if [ ! -d "migrations/versions" ]; then
    flask db init
    flask db migrate
fi

TABLE_COUNT=$(mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -h "$MARIADB_HOSTNAME" -P "$MARIADB_PORT" -D "$MARIADB_DATABASE" -sse \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$MARIADB_DATABASE';") || echo 0

if [ "${TABLE_COUNT:-0}" -eq 0 ]; then
    echo "Empty database, migrating..."
    flask db upgrade
else
    echo "Database already initialized, applying upgrades if any..."
    CURRENT_REVISION=$(mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -h "$MARIADB_HOSTNAME" -P "$MARIADB_PORT" -D "$MARIADB_DATABASE" -sse \
      "SELECT version_num FROM alembic_version LIMIT 1;") || true
    if [ -z "${CURRENT_REVISION:-}" ]; then
        flask db stamp head
    fi
    flask db upgrade
fi

# 4) Arranque Gunicorn escuchando el puerto que inyecta Railway
: "${PORT:=8080}"
exec gunicorn --bind "0.0.0.0:${PORT}" app:app --log-level info --timeout 3600
