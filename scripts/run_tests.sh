#!/bin/bash
set -e

echo "=== Running Backend Tests ==="
cd /app/backend

# Use DATABASE_URL from environment (set by docker-compose) or fallback
export DATABASE_URL="${DATABASE_URL:-postgresql://test:test@db:5432/test_daily_rewards}"

# Skip migrate deploy — API container already ran migrations via dev-entrypoint.sh
# Just generate Prisma client to ensure it works
npx prisma generate --schema=./prisma/schema.prisma 2>&1 || true

# Run vitest tests (they use their own test database URL)
npx vitest run --reporter=verbose 2>&1
BACKEND_RC=$?

echo ""
echo "=== Running Client Lua Tests ==="
cd /app/client

lua -e 'package.path = package.path .. ";./lib/?.lua"' tests/json_tests.lua
JSON_RC=$?

lua -e 'package.path = package.path .. ";./lib/?.lua"' tests/ui_tests.lua
UI_RC=$?

echo ""
echo "=== Running API Integration Tests ==="
if curl -s http://api:3000/health > /dev/null 2>&1; then
    lua -e 'package.path = package.path .. ";./lib/?.lua"' tests/api_tests.lua
    API_RC=$? || true
else
    echo "API backend unavailable — skipping integration tests"
    API_RC=0
fi

echo ""
echo "=== Test Summary ==="
if [ $BACKEND_RC -ne 0 ]; then echo "FAIL: Backend tests"; exit 1; fi
if [ $JSON_RC -ne 0 ]; then echo "FAIL: JSON tests"; exit 1; fi
if [ $UI_RC -ne 0 ]; then echo "FAIL: UI tests"; exit 1; fi
echo "All tests passed!"
