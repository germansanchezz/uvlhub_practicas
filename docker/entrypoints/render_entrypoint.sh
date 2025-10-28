#!/bin/bash

# ---------------------------------------------------------------------------
# Creative Commons CC BY 4.0 - David Romero - Diverso Lab
# ---------------------------------------------------------------------------
# This script is licensed under the Creative Commons Attribution 4.0 
# International License. You are free to share and adapt the material 
# as long as appropriate credit is given, a link to the license is provided, 
# and you indicate if changes were made.
#
# For more details, visit:
# https://creativecommons.org/licenses/by/4.0/
# ---------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status
set -e

# Wait for the database to be ready
sh ./scripts/wait-for-db.sh

# Initialize migrations only if the migrations directory doesn't exist
if [ ! -d "migrations/versions" ]; then
    # Initialize the migration repository
    flask db init
    flask db migrate
fi

# Check if the database is empty (no tables)
DB_TABLE_COUNT=$(mariadb -u "$MARIADB_USER" -p"$MARIADB_PASSWORD" -h "$MARIADB_HOSTNAME" -P "$MARIADB_PORT" -D "$MARIADB_DATABASE" -sse "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$MARIADB_DATABASE';")

if [ "$DB_TABLE_COUNT" -eq 0 ]; then
    echo "Empty database, migrating..."

    # Run the migration process to apply all database schema changes
    flask db upgrade

    # Control autoseed by environment variable AUTO_SEED (default: false)
    # Set AUTO_SEED=true (or 1) in your Render service env vars to enable automatic seeding
    AUTO_SEED=${AUTO_SEED:-"false"}

    if [ "$AUTO_SEED" = "true" ] || [ "$AUTO_SEED" = "1" ]; then
        echo "AUTO_SEED enabled — running seeders (non-interactive)..."
        # Seed the database with initial data (non-interactive)
        # 'rosemary' CLI is provided by the project package installed at image build
        rosemary db:seed -y || python -m rosemary db:seed -y || echo "Seeding failed or rosemary CLI not found"
    else
        echo "AUTO_SEED disabled — skipping automatic seeding. To enable, set AUTO_SEED=true in environment variables."
    fi

else
    echo "Database already initialized (tables: $DB_TABLE_COUNT), updating migrations..."

    # Get the current revision to avoid duplicate stamp
    CURRENT_REVISION=$(mariadb -u $MARIADB_USER -p$MARIADB_PASSWORD -h $MARIADB_HOSTNAME -P $MARIADB_PORT -D $MARIADB_DATABASE -sse "SELECT version_num FROM alembic_version LIMIT 1;")
    
    if [ -z "$CURRENT_REVISION" ]; then
        # If no current revision, stamp with the latest revision
        flask db stamp head
    fi

    # Run the migration process to apply all database schema changes
    flask db upgrade
fi

# Start the application using Gunicorn, binding it to port 80
# Set the logging level to info and the timeout to 3600 seconds
exec gunicorn --bind 0.0.0.0:80 app:app --log-level info --timeout 3600
