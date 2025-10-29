#!/usr/bin/env bash
set -euo pipefail

# Directorio de subidas: por defecto el volumen montado en /app/uploads
: "${UPLOAD_DIR:=/app/uploads}"
mkdir -p "$UPLOAD_DIR"

# Espera opcional a la BD (si tienes el script)
if [ -x "/app/scripts/wait-for-db.sh" ]; then
    /app/scripts/wait-for-db.sh
fi

# Inicializa Alembic si hace falta
if [ ! -d "migrations/versions" ]; then
    flask db init
    flask db migrate
fi

# ¿BD vacía?
TABLE_COUNT=$(mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -h "$MARIADB_HOSTNAME" -P "$MARIADB_PORT" -D "$MARIADB_DATABASE" -sse \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$MARIADB_DATABASE';")

if [ "${TABLE_COUNT:-0}" -eq 0 ]; then
    echo "Empty database, migrating..."
    flask db upgrade
else
    echo "Database already initialized, applying upgrades if any..."
    CURRENT_REVISION=$(mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -h "$MARIADB_HOSTNAME" -P "$MARIADB_PORT" -D "$MARIADB_DATABASE" -sse \
        "SELECT version_num FROM alembic_version LIMIT 1;") || true
    if [ -z "$CURRENT_REVISION" ]; then
        flask db stamp head
    fi
    flask db upgrade
fi

# Importante en Railway: escuchar en 0.0.0.0:$PORT
: "${PORT:=8080}"
exec gunicorn --bind "0.0.0.0:${PORT}" app:app --log-level info --timeout 3600
