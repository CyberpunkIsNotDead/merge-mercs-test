#!/bin/sh
set -e

DB_HOST="${POSTGRES_HOST:-db}"
DB_PORT="${POSTGRES_PORT:-5432}"
DB_NAME="${POSTGRES_DB:-daily_rewards}"
MAX_WAIT=60
WAITED=0

echo "Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."

while ! nc -z "${DB_HOST}" "${DB_PORT}" 2>/dev/null; do
    WAITED=$((WAITED + 1))
    if [ "${WAITED}" -ge "${MAX_WAIT}" ]; then
        echo "ERROR: PostgreSQL did not become ready after ${MAX_WAIT}s"
        exit 1
    fi
    sleep 1
done

echo "PostgreSQL is ready."

# Apply Prisma migrations (idempotent — safe to run repeatedly)
echo "Applying database migrations..."
npx prisma migrate deploy --schema=./prisma/schema.prisma
echo "Migrations applied successfully."

# Execute the CMD
exec "$@"
