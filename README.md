# Daily Rewards - Game Feature Implementation

Built with local AI assistance (Qwen 3.6 via Kilo Code). See [prompts.md](./prompts.md) for the full conversation history and all decisions made during development.

A complete client-server implementation of a daily rewards system with **TypeScript** backend, PostgreSQL database, and LÖVE2D Lua client.

## Quick Start (5 minutes)

### Option A: `start.sh` — one-command setup (recommended for development)

```bash
# Start everything in one go: DB + backend + client (if LÖVE2D installed):
./start.sh

# Or start individual components:
./start.sh backend    # API server only (daemon mode, logs to .backend.log)
./start.sh frontend   # LÖVE2D game window  
./start.sh test       # Run unit tests
./start.sh clean      # Stop everything and remove containers
```

The script automatically: checks dependencies → starts PostgreSQL in Docker → applies Prisma migrations → launches the TypeScript server with hot reload.

Before running, copy `.env.example` to `.env` and adjust values as needed:

```bash
cp .env.example .env
```

### Option B: Docker Compose (recommended for production deployments)

```bash
# Development mode (hot reload, mounted sources):
docker-compose -f docker-compose.dev.yml up

# Production mode (compiled TypeScript, optimized image):
docker-compose -f docker-compose.prod.yml up -d
```

That's it. The database auto-creates and applies migrations on first start. Access the API at `http://localhost:3000`.

### Option C: Manual local development (without start.sh)

```bash
# 1. Start PostgreSQL
docker run -d --name daily-rewards-db \
  -e POSTGRES_DB=daily_rewards \
  -e POSTGRES_USER=dev \
  -e POSTGRES_PASSWORD=dev \
  -p 5432:5432 postgres:16-alpine

# 2. Backend
cd backend && npm install && cp .env.example .env
npx prisma db push      # create tables from schema
npm run dev             # TypeScript with hot reload via tsx

# 3. Tests
npm test                # 16 backend unit + integration tests

# 4. LÖVE2D client (requires love2d installed)
cd ../client && love .
```

---

## Overview

Daily Rewards is a game mechanic where players receive increasing coin rewards for consecutive logins over a 7-day cycle:

| Day | Coins | Cumulative |
|-----|-------|------------|
| 1   | 100   | 100        |
| 2   | 200   | 300        |
| 3   | 300   | 600        |
| 4   | 400   | 1,000      |
| 5   | 500   | 1,500      |
| 6   | 600   | 2,100      |
| 7   | 1000  | 3,100      |

After day 7, the cycle resets to day 1.

### Cooldown System
- **Cooldown**: 5 minutes between claims
- **Reset threshold**: >10 minutes since last claim resets the series to day 1
- All timing logic is enforced server-side (client is untrusted)

## Architecture

```
┌─────────────┐       HTTP/JSON        ┌──────────────┐      PostgreSQL     ┌──────────────┐
│             │   ──────────────────►   │              │   ◄───────────────  │              │
│  LÖVE2D    │                         │  Express.js  │                       │  PostgreSQL  │
│  Client    │   ◄──────────────────   │  (TypeScript)│                       │  Database    │
│  (Lua)     │       HTTP/JSON         │  + JWT Auth  │                       │              │
└─────────────┘ ──────────────────►   └──────────────┘                       └──────────────┘
```

### TypeScript Setup

The backend uses **tsx** to run TypeScript files directly without a build step. This is the simplest approach:

- One dependency (`tsx`) instead of configuring tsc, webpack, or esbuild
- No compilation step that can break during development
- Hot reload with `tsx watch` for fast iteration
- Production: compile once with `tsc` and run optimized JS output

```bash
# Development (runs .ts files directly):
npm run dev          # tsx watch src/server.ts

# Production (compile then run):
npm run build        # tsc compiles to dist/
npm start            # node dist/src/server.js
```

## Docker Deployment

### Environment Files

Two separate compose files for different deployment scenarios:

| File | Purpose | Key Features |
|------|---------|-------------|
| `docker-compose.dev.yml` | Local development | Volume mounts, tsx watch, hot reload |
| `docker-compose.prod.yml` | Production | Compiled TypeScript, optimized image |

### Configuration

Environment variables (create `.env` from the template):

```bash
cp .env.example .env
# Edit .env as needed
```

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | `daily_rewards` | Database name |
| `POSTGRES_USER` | `dev` | PostgreSQL username |
| `POSTGRES_PASSWORD` | `dev` | PostgreSQL password |
| `DB_PORT` | `5432` | Host port for database |
| `API_PORT` | `3000` | Host port for API server |
| `JWT_SECRET` | (varies) | Secret key for JWT signing |

### Commands

```bash
# Development — starts DB + API with hot reload
docker-compose -f docker-compose.dev.yml up          # foreground
docker-compose -f docker-compose.dev.yml up -d        # background

# Production — builds and runs optimized image
docker-compose -f docker-compose.prod.yml build       # build once
docker-compose -f docker-compose.prod.yml up -d        # start
docker-compose -f docker-compose.prod.yml down         # stop + remove volumes

# View logs
docker-compose -f docker-compose.dev.yml logs -f api   # dev logs
docker-compose -f docker-compose.prod.yml logs -f api  # prod logs
```

### How it works

1. **Database** — PostgreSQL container starts, exposes port 5432
2. **Health check** — API waits for DB to become ready (`pg_isready`)
3. **Migrations** — `prisma migrate deploy` applies pending migrations (idempotent)
4. **Server** — Express.js starts on port 3000

## Prerequisites

- **Node.js** >= 18.x (for local development only)
- **npm** >= 9.x
- **Docker** & **docker-compose** v1+ (or Docker Desktop with Compose plugin)
- **LÖVE2D** >= 11.5 (for client, optional — requires separate installation) - https://love2d.org/

## Installation & Setup

### Backend

```bash
cd backend

# Install dependencies (includes TypeScript + tsx)
npm install

# Development mode (runs TypeScript directly with tsx + auto-reload):
npm run dev          # tsx watch src/server.ts

# Production: compile TypeScript then run
npm run build        # tsc compiles to dist/
npm start            # node dist/src/server.js

# Test suite (16 tests)
npm test             # vitest run
```

### Client

The LÖVE2D client runs independently of the backend.

```bash
cd client

# Requires: love2d installed on your system
# Linux: sudo apt install love
# macOS: brew install --cask love
# Windows: https://love2d.org/
love .
```

## API Documentation

### Authentication

**POST /auth/guest**

Creates a new guest user and returns authentication credentials.

Request: (none)
Response:
```json
{
  "user_id": "uuid-string",
  "token": "jwt-token-string"
}
```

### Daily Rewards - Get State

**GET /daily-rewards**

Returns the current state of daily rewards for the authenticated user.

Headers: `Authorization: Bearer <token>`

Response:
```json
{
  "current_day": 3,
  "total_coins": 600,
  "can_claim": false,
  "cooldown_until": "2024-01-01T00:10:00.000Z",
  "coins_to_win": 300,
  "reset_needed": false
}
```

### Daily Rewards - Claim Reward

**POST /daily-rewards/claim**

Claims the daily reward for the current day.

Headers: `Authorization: Bearer <token>`

Response (success):
```json
{
  "success": true,
  "coins_awarded": 300,
  "current_day": 4,
  "total_coins": 900,
  "reset_occurred": false
}
```

Response (cooldown active - HTTP 409):
```json
{
  "success": false,
  "error": "COOLDOWN_ACTIVE",
  "message": "Come back in 3 minutes",
  "retry_after_seconds": 180
}
```

## Testing

### Backend Tests (Vitest)

```bash
cd backend
npm test              # 16 unit + integration tests
```

### Client Tests (Busted via Docker)

```bash
./start.sh test         # Runs all tests: backend vitest + client busted
docker-compose -f docker-compose.test.yml up   # or run directly
```

The test suite includes:
- **Backend**: Service layer unit tests, Prisma integration tests (16 tests)
- **Client JSON library**: Pure-Lua encoder/decoder unit tests (~20 tests)
- **Client UI logic**: Pure function tests for formatting, colors, messages (~30 tests)
- **API Integration**: Lua client HTTP request/response tests against running API container (~7 tests)

---

## Project Structure

```
daily-rewards/
├── backend/
│   ├── src/
│   │   ├── server.ts              # Express app entry point (TypeScript)
│   │   ├── routes/
│   │   │   ├── auth.ts            # POST /auth/guest
│   │   │   └── dailyRewards.ts    # GET/POST /daily-rewards*
│   │   ├── services/
│   │   │   ├── authService.ts     # JWT generation/validation
│   │   │   └── dailyRewardService.ts  # Core game logic
│   │   ├── middleware/
│   │   │   └── authMiddleware.ts  # Token verification middleware
│   │   ├── utils/
│   │   │   └── constants.ts       # Reward schedule, cooldown times
│   │   └── types/
│   │       └── index.ts           # Shared TypeScript interfaces
│   ├── docker/
│   │   ├── entrypoint.sh          # Production startup script
│   │   └── dev-entrypoint.sh      # Development startup script
│   ├── prisma/
│   │   └── schema.prisma          # Database schema
│   ├── tests/
│   │   ├── services.test.ts       # Unit + integration tests (16 tests)
│   │   └── setup.ts               # Test cleanup hook
│   ├── Dockerfile.dev             # Development image (tsx watch, volumes)
│   ├── Dockerfile.prod            # Production image (compiled TS)
│   ├── vitest.config.mjs          # Vitest configuration
│   ├── tsconfig.json              # TypeScript config
│   ├── package.json
│   └── .env.example
├── client/
│   ├── main.lua                   # Main game screen with UI
│   ├── conf.lua                   # LÖVE2D window config
│   ├── lib/
│   │   ├── api.lua                # HTTP API client for Lua
│   │   ├── json.lua               # Pure-Lua JSON encoder/decoder
│   │   └── ui.lua                 # UI helper functions (pure)
│   └── tests/
│       ├── api_tests.lua          # API integration tests
│       ├── json_tests.lua         # JSON library unit tests
│       └── ui_tests.lua           # UI logic unit tests
├── scripts/
│   └── run_tests.sh               # Test runner for Docker test environment
├── docker-compose.dev.yml         # Development Docker setup
├── docker-compose.prod.yml        # Production Docker setup
├── docker-compose.test.yml        # Test Docker setup (DB + API + tests)
├── Dockerfile.test                # Combined test image (Node 22 + Lua 5.3 + busted)
├── start.sh                       # Unified startup script (DB + backend + client)
├── .env.example                   # Environment template (root level)
└── README.md                      # This file
```

## Security Considerations

- JWT tokens are hashed before storage using bcrypt
- Tokens have a short expiry (1 hour by default)
- All timing logic is enforced server-side; the client is untrusted
- Database transactions prevent race conditions on concurrent claim attempts

## Design Decisions

### 7-Day Cyclic Reset
After day 7, rewards cycle back to day 1 indefinitely. This allows continuous daily engagement without hard stops.

### Cooldown vs Series Reset
- **5-minute cooldown**: Prevents rapid successive claims but allows regular play sessions
- **10-minute reset threshold**: Penalizes players who take long breaks by resetting their series, encouraging consistent daily engagement

### Day Tracking
The `current_day` in the database represents the day that was LAST CLAIMED. On first claim (no previous history), it stays at 1. Subsequent claims after cooldown advance to the next day.

## License

This is a test project created for demonstration purposes.
