# Phase 0 — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the empty-but-correct skeleton of the new `wbap-api` service: a new repo, Node 20 + Hono + Drizzle + Zod + Postgres 16 wiring, dev Docker stack, observability hooks, distroless production image, and CI with security gates. Caddy already routes 100% to SHM and will continue to until later phases flip flags.

**Architecture:** Plain Node 20 LTS service running Hono. Drizzle ORM against a dedicated Postgres 16 instance. Redis for sessions/queue. Tests via Vitest + testcontainers for integration. Distroless multi-stage Docker. GitHub Actions CI with Semgrep + npm audit + Trivy. Caddy reverse-proxy in front, currently a passthrough.

**Tech Stack:** Node 20.x, pnpm 10, TypeScript 5.x, Hono 4, Drizzle ORM (latest), Zod 3, pino, prom-client, @opentelemetry/sdk-node, BullMQ, ioredis, Vitest, @testcontainers/postgresql, ESLint 9 (flat config), Prettier 3, Caddy 2, Docker Compose v2.

**Repo location:** `/Users/qwertyhq/code/wbap-api/` (new). The spec lives in the SHM repo at `docs/superpowers/specs/2026-05-07-shm-replacement-design.md`.

**This plan creates the new repo from scratch.** Task 1 initializes it; all subsequent tasks operate inside it.

---

## File Structure (after Phase 0)

```
/Users/qwertyhq/code/wbap-api/
├── .github/
│   └── workflows/
│       └── ci.yml                       # Lint, typecheck, test, semgrep, audit, trivy, build
├── .vscode/
│   └── settings.json                    # Editor consistency
├── caddy/
│   ├── Caddyfile                        # Reverse-proxy with feature flags
│   └── README.md                        # How feature flags work
├── docker/
│   ├── Dockerfile                       # Multi-stage distroless production image
│   └── docker-compose.dev.yml           # Local dev: PG, Redis, Caddy, app
├── drizzle/
│   ├── 0000_init_schemas.sql            # First migration: create schemas + version table
│   └── meta/                            # Auto-managed by drizzle-kit
├── src/
│   ├── app.ts                           # Hono app composition (routes, middleware)
│   ├── config.ts                        # Env loading + Zod validation
│   ├── server.ts                        # Entry point: starts HTTP listener
│   ├── db/
│   │   ├── client.ts                    # Drizzle PG pool factory
│   │   └── schema.ts                    # Initial schemas (empty stubs by area)
│   ├── redis/
│   │   └── client.ts                    # ioredis factory
│   ├── observability/
│   │   ├── logger.ts                    # pino + request-id propagation
│   │   ├── metrics.ts                   # prom-client registry + HTTP middleware
│   │   └── tracing.ts                   # OTel SDK init (no-op exporter by default)
│   ├── middleware/
│   │   ├── request-id.ts                # X-Request-Id propagation
│   │   └── error-handler.ts             # Catch-all, normalize to JSON
│   └── routes/
│       ├── health.ts                    # /health (liveness)
│       ├── ready.ts                     # /ready (readiness with DB+Redis)
│       └── hello.ts                     # /hello (Phase 0 sanity endpoint)
├── tests/
│   ├── setup.ts                         # Vitest global setup
│   ├── integration/
│   │   ├── hello.test.ts                # E2E hello-world via supertest-like client
│   │   ├── health.test.ts               # Health/ready checks
│   │   └── db.test.ts                   # Drizzle connection + migration applied
│   └── unit/
│       └── config.test.ts               # Env validation
├── .dockerignore
├── .env.example                         # Documents required env vars
├── .eslintrc.cjs                        # (or eslint.config.js — flat config)
├── .gitignore
├── .nvmrc                               # Pin to Node 20 LTS for CI/dev parity
├── .prettierrc.json
├── drizzle.config.ts                    # drizzle-kit config
├── package.json
├── pnpm-lock.yaml
├── README.md
├── tsconfig.json
└── vitest.config.ts
```

**Module boundaries:**
- `src/app.ts` composes routes and middleware. Knows nothing about how the server is started.
- `src/server.ts` is the only file that imports `node:http` / `@hono/node-server` and calls `serve()`. Keeps `app.ts` testable in-process.
- `src/config.ts` is the single source of truth for env vars; everywhere else reads from this. Failure to validate env crashes at boot, never at runtime.
- `src/db/`, `src/redis/`, `src/observability/` are infrastructure modules — pure providers, no business logic. They will be reused by every subsequent Phase.
- `src/routes/` contains route handlers. One file per concern. Each handler imports its dependencies explicitly.

---

## Conventions

- **Named exports only.** Matches WBAP frontend convention. ESLint rule blocks default exports.
- **`@/` import alias** points to `src/` (configured in `tsconfig.json` and Vitest).
- **All async failures are caught** by the error-handler middleware; handlers can throw freely.
- **Every test has the form `it("does specific thing")`** — no nested describes deeper than 2 levels.
- **Commit messages**: Conventional Commits (`feat:`, `chore:`, `test:`, `docs:`, `ci:`, `build:`).
- **Frequent commits**: one commit per task minimum, more is fine.

---

## Task 1: Initialize repo with package.json and pnpm

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/.gitignore`
- Create: `/Users/qwertyhq/code/wbap-api/.nvmrc`
- Create: `/Users/qwertyhq/code/wbap-api/package.json`
- Create: `/Users/qwertyhq/code/wbap-api/README.md`

- [ ] **Step 1.1: Create directory and initialize git**

```bash
mkdir -p /Users/qwertyhq/code/wbap-api
cd /Users/qwertyhq/code/wbap-api
git init
```

Expected: empty repo on default branch.

- [ ] **Step 1.2: Create `.gitignore`**

Write `/Users/qwertyhq/code/wbap-api/.gitignore`:

```gitignore
# Dependencies
node_modules/
.pnpm-store/

# Build
dist/
*.tsbuildinfo

# Test artifacts
coverage/
.vitest-cache/

# Env
.env
.env.local
.env.*.local
!.env.example

# OS
.DS_Store
Thumbs.db

# IDE
.idea/

# Logs
*.log
logs/

# Drizzle journal — keep meta/, ignore generated journal artifacts
drizzle/meta/_journal.json.bak
```

- [ ] **Step 1.3: Pin Node version**

Write `/Users/qwertyhq/code/wbap-api/.nvmrc`:

```
20
```

- [ ] **Step 1.4: Create `package.json`**

Write `/Users/qwertyhq/code/wbap-api/package.json`:

```json
{
  "name": "wbap-api",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=20 <21"
  },
  "packageManager": "pnpm@10.15.0",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.build.json",
    "start": "node dist/server.js",
    "lint": "eslint .",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "db:generate": "drizzle-kit generate",
    "db:migrate": "tsx src/db/migrate.ts",
    "db:studio": "drizzle-kit studio"
  }
}
```

- [ ] **Step 1.5: Stub README**

Write `/Users/qwertyhq/code/wbap-api/README.md`:

```markdown
# wbap-api

New TypeScript backend replacing SHM. See design spec at the SHM repo:
`docs/superpowers/specs/2026-05-07-shm-replacement-design.md`.

## Quickstart (dev)

Requires Docker, Node 20 LTS, pnpm 10.

\`\`\`bash
pnpm install
docker compose -f docker/docker-compose.dev.yml up -d
pnpm db:migrate
pnpm dev
curl http://localhost:8080/health
\`\`\`

## Status

Phase 0 (Foundation) — skeleton only.
```

- [ ] **Step 1.6: First commit**

```bash
cd /Users/qwertyhq/code/wbap-api
git add .gitignore .nvmrc package.json README.md
git commit -m "chore: initialize wbap-api repo"
```

---

## Task 2: TypeScript + path alias config

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/tsconfig.json`
- Create: `/Users/qwertyhq/code/wbap-api/tsconfig.build.json`
- Modify: `/Users/qwertyhq/code/wbap-api/package.json` (add devDeps)

- [ ] **Step 2.1: Install TypeScript devDependencies**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add -D typescript@^5.5.0 @types/node@^20 tsx@^4.16.0
```

Expected: pnpm-lock.yaml created, TS 5.5+, @types/node v20.

- [ ] **Step 2.2: Create base `tsconfig.json`**

Write `/Users/qwertyhq/code/wbap-api/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "types": ["node"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "exactOptionalPropertyTypes": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": false,
    "noEmit": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src/**/*", "tests/**/*", "drizzle.config.ts", "vitest.config.ts"],
  "exclude": ["node_modules", "dist"]
}
```

- [ ] **Step 2.3: Create `tsconfig.build.json` (used by `pnpm build`)**

Write `/Users/qwertyhq/code/wbap-api/tsconfig.build.json`:

```json
{
  "extends": "./tsconfig.json",
  "compilerOptions": {
    "noEmit": false,
    "outDir": "dist",
    "rootDir": "src",
    "declaration": false,
    "sourceMap": true,
    "removeComments": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

- [ ] **Step 2.4: Verify typecheck on empty src**

```bash
mkdir -p src
echo "export {};" > src/server.ts
pnpm typecheck
```

Expected: exits 0, no errors.

- [ ] **Step 2.5: Commit**

```bash
git add tsconfig.json tsconfig.build.json package.json pnpm-lock.yaml src/server.ts
git commit -m "build: add TypeScript config with strict mode and @/ alias"
```

---

## Task 3: Linter + formatter + named-exports rule

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/eslint.config.js`
- Create: `/Users/qwertyhq/code/wbap-api/.prettierrc.json`
- Create: `/Users/qwertyhq/code/wbap-api/.prettierignore`

- [ ] **Step 3.1: Install ESLint + Prettier devDependencies**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add -D eslint@^9 typescript-eslint@^8 @eslint/js@^9 eslint-config-prettier@^9 prettier@^3
```

- [ ] **Step 3.2: Create flat ESLint config**

Write `/Users/qwertyhq/code/wbap-api/eslint.config.js`:

```javascript
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import prettier from "eslint-config-prettier";

export default [
  { ignores: ["dist", "node_modules", "drizzle/meta"] },
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector: "ExportDefaultDeclaration",
          message: "Default exports are forbidden. Use named exports.",
        },
      ],
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports", fixStyle: "separate-type-imports" },
      ],
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/await-thenable": "error",
      "@typescript-eslint/no-misused-promises": "error",
    },
  },
  prettier,
];
```

- [ ] **Step 3.3: Create Prettier config**

Write `/Users/qwertyhq/code/wbap-api/.prettierrc.json`:

```json
{
  "semi": true,
  "singleQuote": false,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

- [ ] **Step 3.4: Create `.prettierignore`**

Write `/Users/qwertyhq/code/wbap-api/.prettierignore`:

```
dist
node_modules
pnpm-lock.yaml
drizzle/meta
coverage
```

- [ ] **Step 3.5: Verify lint runs (no source files yet means clean)**

```bash
pnpm lint
pnpm format:check
```

Expected: both exit 0.

- [ ] **Step 3.6: Commit**

```bash
git add eslint.config.js .prettierrc.json .prettierignore package.json pnpm-lock.yaml
git commit -m "build: add ESLint flat config + Prettier with no-default-exports rule"
```

---

## Task 4: Config module with Zod env validation (TDD)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/config.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/unit/config.test.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/setup.ts`
- Create: `/Users/qwertyhq/code/wbap-api/vitest.config.ts`
- Create: `/Users/qwertyhq/code/wbap-api/.env.example`

- [ ] **Step 4.1: Install Zod and Vitest**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add zod@^3.23
pnpm add -D vitest@^2 @vitest/coverage-v8@^2
```

- [ ] **Step 4.2: Create Vitest config**

Write `/Users/qwertyhq/code/wbap-api/vitest.config.ts`:

```typescript
import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

export default defineConfig({
  test: {
    globals: false,
    environment: "node",
    setupFiles: ["./tests/setup.ts"],
    include: ["tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov"],
      include: ["src/**/*.ts"],
      exclude: ["src/**/*.test.ts", "src/server.ts"],
    },
    testTimeout: 30_000,
  },
  resolve: {
    alias: {
      "@": resolve(__dirname, "src"),
    },
  },
});
```

- [ ] **Step 4.3: Create test setup placeholder**

Write `/Users/qwertyhq/code/wbap-api/tests/setup.ts`:

```typescript
// Global test setup. Add testcontainers bootstrap here in later tasks.
```

- [ ] **Step 4.4: Write failing test for config validation**

Write `/Users/qwertyhq/code/wbap-api/tests/unit/config.test.ts`:

```typescript
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { loadConfig } from "@/config";

describe("loadConfig", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    for (const key of Object.keys(process.env)) {
      if (key.startsWith("WBAP_")) delete process.env[key];
    }
    delete process.env.NODE_ENV;
    delete process.env.PORT;
    delete process.env.DATABASE_URL;
    delete process.env.REDIS_URL;
  });

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("returns parsed config when all required env vars are valid", () => {
    process.env.NODE_ENV = "development";
    process.env.PORT = "8080";
    process.env.DATABASE_URL = "postgres://wbap:wbap@localhost:5432/wbap";
    process.env.REDIS_URL = "redis://localhost:6379";

    const cfg = loadConfig();

    expect(cfg.nodeEnv).toBe("development");
    expect(cfg.port).toBe(8080);
    expect(cfg.databaseUrl).toBe("postgres://wbap:wbap@localhost:5432/wbap");
    expect(cfg.redisUrl).toBe("redis://localhost:6379");
  });

  it("throws on missing DATABASE_URL", () => {
    process.env.NODE_ENV = "development";
    process.env.PORT = "8080";
    process.env.REDIS_URL = "redis://localhost:6379";

    expect(() => loadConfig()).toThrow(/DATABASE_URL/);
  });

  it("throws on non-numeric PORT", () => {
    process.env.NODE_ENV = "development";
    process.env.PORT = "not-a-number";
    process.env.DATABASE_URL = "postgres://wbap:wbap@localhost:5432/wbap";
    process.env.REDIS_URL = "redis://localhost:6379";

    expect(() => loadConfig()).toThrow();
  });

  it("rejects unknown NODE_ENV", () => {
    process.env.NODE_ENV = "magical";
    process.env.PORT = "8080";
    process.env.DATABASE_URL = "postgres://wbap:wbap@localhost:5432/wbap";
    process.env.REDIS_URL = "redis://localhost:6379";

    expect(() => loadConfig()).toThrow();
  });
});
```

- [ ] **Step 4.5: Run failing test**

```bash
pnpm test
```

Expected: fails with "Cannot find module '@/config'".

- [ ] **Step 4.6: Implement `src/config.ts`**

Write `/Users/qwertyhq/code/wbap-api/src/config.ts`:

```typescript
import { z } from "zod";

const ConfigSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]),
  PORT: z.coerce.number().int().positive().max(65535),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),
});

export type Config = {
  nodeEnv: "development" | "test" | "production";
  port: number;
  databaseUrl: string;
  redisUrl: string;
  logLevel: "fatal" | "error" | "warn" | "info" | "debug" | "trace";
};

export function loadConfig(): Config {
  const parsed = ConfigSchema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  return {
    nodeEnv: parsed.data.NODE_ENV,
    port: parsed.data.PORT,
    databaseUrl: parsed.data.DATABASE_URL,
    redisUrl: parsed.data.REDIS_URL,
    logLevel: parsed.data.LOG_LEVEL,
  };
}
```

- [ ] **Step 4.7: Run tests to confirm pass**

```bash
pnpm test
```

Expected: 4 tests pass.

- [ ] **Step 4.8: Document required env in `.env.example`**

Write `/Users/qwertyhq/code/wbap-api/.env.example`:

```env
NODE_ENV=development
PORT=8080
DATABASE_URL=postgres://wbap:wbap@localhost:5432/wbap_billing
REDIS_URL=redis://localhost:6379
LOG_LEVEL=debug
```

- [ ] **Step 4.9: Commit**

```bash
git add src/config.ts tests/unit/config.test.ts tests/setup.ts vitest.config.ts .env.example package.json pnpm-lock.yaml
git commit -m "feat(config): add zod-validated env config loader"
```

---

## Task 5: Pino logger + request-id middleware (TDD)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/observability/logger.ts`
- Create: `/Users/qwertyhq/code/wbap-api/src/middleware/request-id.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/unit/request-id.test.ts`

- [ ] **Step 5.1: Install pino and Hono**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add pino@^9 hono@^4
pnpm add -D pino-pretty@^11
```

- [ ] **Step 5.2: Implement logger**

Write `/Users/qwertyhq/code/wbap-api/src/observability/logger.ts`:

```typescript
import pino from "pino";
import type { Config } from "@/config";

export function createLogger(cfg: Pick<Config, "nodeEnv" | "logLevel">): pino.Logger {
  const isDev = cfg.nodeEnv === "development";
  return pino({
    level: cfg.logLevel,
    base: { service: "wbap-api" },
    timestamp: pino.stdTimeFunctions.isoTime,
    redact: {
      paths: ["req.headers.authorization", "req.headers.cookie", "*.password", "*.token"],
      censor: "[REDACTED]",
    },
    transport: isDev
      ? {
          target: "pino-pretty",
          options: { colorize: true, singleLine: false, ignore: "pid,hostname" },
        }
      : undefined,
  });
}
```

- [ ] **Step 5.3: Write failing test for request-id middleware**

Write `/Users/qwertyhq/code/wbap-api/tests/unit/request-id.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { requestId } from "@/middleware/request-id";

describe("requestId middleware", () => {
  it("propagates an existing X-Request-Id header to the response", async () => {
    const app = new Hono().use("*", requestId()).get("/", (c) => c.text("ok"));
    const res = await app.request("/", { headers: { "X-Request-Id": "abc-123" } });
    expect(res.headers.get("X-Request-Id")).toBe("abc-123");
  });

  it("generates a UUID when no X-Request-Id is present", async () => {
    const app = new Hono().use("*", requestId()).get("/", (c) => c.text("ok"));
    const res = await app.request("/");
    const id = res.headers.get("X-Request-Id");
    expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  });

  it("exposes request id on the context", async () => {
    const app = new Hono()
      .use("*", requestId())
      .get("/", (c) => c.text(c.get("requestId")));
    const res = await app.request("/", { headers: { "X-Request-Id": "ctx-test" } });
    expect(await res.text()).toBe("ctx-test");
  });
});
```

- [ ] **Step 5.4: Run failing test**

```bash
pnpm test
```

Expected: fails with "Cannot find module '@/middleware/request-id'".

- [ ] **Step 5.5: Implement request-id middleware**

Write `/Users/qwertyhq/code/wbap-api/src/middleware/request-id.ts`:

```typescript
import type { MiddlewareHandler } from "hono";
import { randomUUID } from "node:crypto";

declare module "hono" {
  interface ContextVariableMap {
    requestId: string;
  }
}

export function requestId(): MiddlewareHandler {
  return async (c, next) => {
    const incoming = c.req.header("X-Request-Id");
    const id = incoming && incoming.length > 0 ? incoming : randomUUID();
    c.set("requestId", id);
    c.header("X-Request-Id", id);
    await next();
  };
}
```

- [ ] **Step 5.6: Run tests to confirm pass**

```bash
pnpm test
```

Expected: all tests pass (config tests still passing too).

- [ ] **Step 5.7: Commit**

```bash
git add src/observability/logger.ts src/middleware/request-id.ts tests/unit/request-id.test.ts package.json pnpm-lock.yaml
git commit -m "feat(observability): add pino logger and request-id middleware"
```

---

## Task 6: Health and ready endpoints (TDD)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/routes/health.ts`
- Create: `/Users/qwertyhq/code/wbap-api/src/routes/ready.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/integration/health.test.ts`

- [ ] **Step 6.1: Write failing test for /health and /ready (degraded path only)**

Write `/Users/qwertyhq/code/wbap-api/tests/integration/health.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { healthRoute } from "@/routes/health";
import { readyRoute } from "@/routes/ready";

describe("/health", () => {
  it("returns 200 with ok body", async () => {
    const app = new Hono().route("/", healthRoute());
    const res = await app.request("/health");
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string };
    expect(body.status).toBe("ok");
  });
});

describe("/ready", () => {
  it("returns 200 when all probes pass", async () => {
    const probes = {
      db: async () => true,
      redis: async () => true,
    };
    const app = new Hono().route("/", readyRoute(probes));
    const res = await app.request("/ready");
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string; checks: Record<string, string> };
    expect(body.status).toBe("ok");
    expect(body.checks.db).toBe("ok");
    expect(body.checks.redis).toBe("ok");
  });

  it("returns 503 when any probe fails", async () => {
    const probes = {
      db: async () => false,
      redis: async () => true,
    };
    const app = new Hono().route("/", readyRoute(probes));
    const res = await app.request("/ready");
    expect(res.status).toBe(503);
    const body = (await res.json()) as { status: string; checks: Record<string, string> };
    expect(body.status).toBe("degraded");
    expect(body.checks.db).toBe("fail");
    expect(body.checks.redis).toBe("ok");
  });

  it("returns 503 when a probe throws", async () => {
    const probes = {
      db: async () => {
        throw new Error("conn refused");
      },
      redis: async () => true,
    };
    const app = new Hono().route("/", readyRoute(probes));
    const res = await app.request("/ready");
    expect(res.status).toBe(503);
  });
});
```

- [ ] **Step 6.2: Run failing test**

```bash
pnpm test
```

Expected: fails (modules not found).

- [ ] **Step 6.3: Implement `/health`**

Write `/Users/qwertyhq/code/wbap-api/src/routes/health.ts`:

```typescript
import { Hono } from "hono";

export function healthRoute(): Hono {
  const app = new Hono();
  app.get("/health", (c) => c.json({ status: "ok" }));
  return app;
}
```

- [ ] **Step 6.4: Implement `/ready`**

Write `/Users/qwertyhq/code/wbap-api/src/routes/ready.ts`:

```typescript
import { Hono } from "hono";

export type ReadinessProbe = () => Promise<boolean>;

export type ReadinessProbes = Record<string, ReadinessProbe>;

export function readyRoute(probes: ReadinessProbes): Hono {
  const app = new Hono();
  app.get("/ready", async (c) => {
    const entries = await Promise.all(
      Object.entries(probes).map(async ([name, probe]) => {
        try {
          const ok = await probe();
          return [name, ok ? "ok" : "fail"] as const;
        } catch {
          return [name, "fail"] as const;
        }
      }),
    );
    const checks = Object.fromEntries(entries);
    const allOk = entries.every(([, status]) => status === "ok");
    return c.json(
      { status: allOk ? "ok" : "degraded", checks },
      allOk ? 200 : 503,
    );
  });
  return app;
}
```

- [ ] **Step 6.5: Run tests to confirm pass**

```bash
pnpm test
```

Expected: all tests pass.

- [ ] **Step 6.6: Commit**

```bash
git add src/routes/health.ts src/routes/ready.ts tests/integration/health.test.ts
git commit -m "feat(routes): add /health and /ready endpoints"
```

---

## Task 7: Hello endpoint with Zod validation (TDD)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/routes/hello.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/integration/hello.test.ts`

- [ ] **Step 7.1: Install Hono Zod validator**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add @hono/zod-validator@^0.4
```

- [ ] **Step 7.2: Write failing test for /hello**

Write `/Users/qwertyhq/code/wbap-api/tests/integration/hello.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { helloRoute } from "@/routes/hello";

describe("/hello", () => {
  it("GET returns greeting with default name", async () => {
    const app = new Hono().route("/", helloRoute());
    const res = await app.request("/hello");
    expect(res.status).toBe(200);
    const body = (await res.json()) as { greeting: string };
    expect(body.greeting).toBe("hello, world");
  });

  it("GET accepts ?name= query and greets that name", async () => {
    const app = new Hono().route("/", helloRoute());
    const res = await app.request("/hello?name=phase0");
    expect(res.status).toBe(200);
    const body = (await res.json()) as { greeting: string };
    expect(body.greeting).toBe("hello, phase0");
  });

  it("rejects ?name longer than 64 chars with 400", async () => {
    const app = new Hono().route("/", helloRoute());
    const long = "a".repeat(65);
    const res = await app.request(`/hello?name=${long}`);
    expect(res.status).toBe(400);
  });
});
```

- [ ] **Step 7.3: Run failing test**

```bash
pnpm test
```

Expected: fails (helloRoute not found).

- [ ] **Step 7.4: Implement `/hello`**

Write `/Users/qwertyhq/code/wbap-api/src/routes/hello.ts`:

```typescript
import { Hono } from "hono";
import { zValidator } from "@hono/zod-validator";
import { z } from "zod";

const QuerySchema = z.object({
  name: z.string().min(1).max(64).default("world"),
});

export function helloRoute(): Hono {
  const app = new Hono();
  app.get("/hello", zValidator("query", QuerySchema), (c) => {
    const { name } = c.req.valid("query");
    return c.json({ greeting: `hello, ${name}` });
  });
  return app;
}
```

- [ ] **Step 7.5: Run tests to confirm pass**

```bash
pnpm test
```

Expected: all hello tests pass.

- [ ] **Step 7.6: Commit**

```bash
git add src/routes/hello.ts tests/integration/hello.test.ts package.json pnpm-lock.yaml
git commit -m "feat(routes): add /hello endpoint with zod query validation"
```

---

## Task 8: Error handler middleware (TDD)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/middleware/error-handler.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/unit/error-handler.test.ts`

- [ ] **Step 8.1: Write failing test**

Write `/Users/qwertyhq/code/wbap-api/tests/unit/error-handler.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { errorHandler } from "@/middleware/error-handler";

describe("errorHandler", () => {
  it("renders generic 500 JSON for unknown errors", async () => {
    const app = new Hono();
    app.onError(errorHandler());
    app.get("/boom", () => {
      throw new Error("boom");
    });
    const res = await app.request("/boom");
    expect(res.status).toBe(500);
    const body = (await res.json()) as { error: string; requestId: string | null };
    expect(body.error).toBe("internal_error");
  });

  it("renders the HTTPException status and message", async () => {
    const app = new Hono();
    app.onError(errorHandler());
    app.get("/forbidden", () => {
      throw new HTTPException(403, { message: "no" });
    });
    const res = await app.request("/forbidden");
    expect(res.status).toBe(403);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("no");
  });

  it("includes request id when set on context", async () => {
    const app = new Hono();
    app.use("*", async (c, next) => {
      c.set("requestId", "rid-1");
      await next();
    });
    app.onError(errorHandler());
    app.get("/boom", () => {
      throw new Error("boom");
    });
    const res = await app.request("/boom");
    const body = (await res.json()) as { requestId: string };
    expect(body.requestId).toBe("rid-1");
  });
});
```

- [ ] **Step 8.2: Run failing test**

```bash
pnpm test
```

Expected: fails (errorHandler not found).

- [ ] **Step 8.3: Implement error handler**

Write `/Users/qwertyhq/code/wbap-api/src/middleware/error-handler.ts`:

```typescript
import type { ErrorHandler } from "hono";
import { HTTPException } from "hono/http-exception";
import type { ContentfulStatusCode } from "hono/utils/http-status";

export function errorHandler(): ErrorHandler {
  return (err, c) => {
    const requestId = c.get("requestId") ?? null;
    if (err instanceof HTTPException) {
      return c.json(
        { error: err.message, requestId },
        err.status as ContentfulStatusCode,
      );
    }
    return c.json({ error: "internal_error", requestId }, 500);
  };
}
```

- [ ] **Step 8.4: Run tests to confirm pass**

```bash
pnpm test
```

Expected: all error-handler tests pass.

- [ ] **Step 8.5: Commit**

```bash
git add src/middleware/error-handler.ts tests/unit/error-handler.test.ts
git commit -m "feat(middleware): add error handler with HTTPException + generic fallback"
```

---

## Task 9: Compose `app.ts` and `server.ts` entry points

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/app.ts`
- Modify: `/Users/qwertyhq/code/wbap-api/src/server.ts`

- [ ] **Step 9.1: Install Hono Node adapter**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add @hono/node-server@^1
```

- [ ] **Step 9.2: Compose Hono app**

Write `/Users/qwertyhq/code/wbap-api/src/app.ts`:

```typescript
import { Hono } from "hono";
import { requestId } from "@/middleware/request-id";
import { errorHandler } from "@/middleware/error-handler";
import { helloRoute } from "@/routes/hello";
import { healthRoute } from "@/routes/health";
import { readyRoute, type ReadinessProbes } from "@/routes/ready";

export type AppDeps = {
  probes: ReadinessProbes;
};

export function createApp(deps: AppDeps): Hono {
  const app = new Hono();
  app.use("*", requestId());
  app.onError(errorHandler());
  app.route("/", healthRoute());
  app.route("/", readyRoute(deps.probes));
  app.route("/", helloRoute());
  return app;
}
```

- [ ] **Step 9.3: Wire entry point**

Replace `/Users/qwertyhq/code/wbap-api/src/server.ts`:

```typescript
import { serve } from "@hono/node-server";
import { loadConfig } from "@/config";
import { createApp } from "@/app";
import { createLogger } from "@/observability/logger";

async function main(): Promise<void> {
  const cfg = loadConfig();
  const log = createLogger(cfg);

  const app = createApp({
    probes: {
      db: async () => true,
      redis: async () => true,
    },
  });

  serve({ fetch: app.fetch, port: cfg.port }, ({ port }) => {
    log.info({ port, nodeEnv: cfg.nodeEnv }, "wbap-api started");
  });
}

main().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error("boot failure", err);
  process.exit(1);
});
```

- [ ] **Step 9.4: Smoke-run dev server**

```bash
cd /Users/qwertyhq/code/wbap-api
cp .env.example .env
NODE_ENV=development PORT=8080 DATABASE_URL=postgres://x/y REDIS_URL=redis://localhost:6379 pnpm dev &
sleep 2
curl -s http://localhost:8080/health
curl -s http://localhost:8080/hello?name=phase0
kill %1
```

Expected:
- `/health` → `{"status":"ok"}`
- `/hello?name=phase0` → `{"greeting":"hello, phase0"}`
- log output contains `wbap-api started`.

- [ ] **Step 9.5: Run all tests**

```bash
pnpm test
pnpm typecheck
pnpm lint
```

Expected: all green.

- [ ] **Step 9.6: Commit**

```bash
git add src/app.ts src/server.ts package.json pnpm-lock.yaml
git commit -m "feat(server): compose app and start HTTP listener"
```

---

## Task 10: Docker Compose dev stack (Postgres + Redis)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/docker/docker-compose.dev.yml`

- [ ] **Step 10.1: Write Compose file**

Write `/Users/qwertyhq/code/wbap-api/docker/docker-compose.dev.yml`:

```yaml
name: wbap-api-dev

services:
  postgres:
    image: postgres:16-alpine
    container_name: wbap-api-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: wbap
      POSTGRES_PASSWORD: wbap
      POSTGRES_DB: wbap_billing
    ports:
      - "5432:5432"
    volumes:
      - wbap-api-pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U wbap -d wbap_billing"]
      interval: 5s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: wbap-api-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    ports:
      - "6379:6379"
    volumes:
      - wbap-api-redisdata:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  wbap-api-pgdata:
  wbap-api-redisdata:
```

- [ ] **Step 10.2: Bring stack up and verify**

```bash
cd /Users/qwertyhq/code/wbap-api
docker compose -f docker/docker-compose.dev.yml up -d
docker compose -f docker/docker-compose.dev.yml ps
docker exec wbap-api-postgres pg_isready -U wbap -d wbap_billing
docker exec wbap-api-redis redis-cli ping
```

Expected:
- both containers `Up (healthy)` after ~10 s
- pg_isready prints `accepting connections`
- redis-cli prints `PONG`.

- [ ] **Step 10.3: Commit**

```bash
git add docker/docker-compose.dev.yml
git commit -m "build(dev): add docker compose stack for postgres and redis"
```

---

## Task 11: Drizzle setup + first migration (schemas + version table)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/drizzle.config.ts`
- Create: `/Users/qwertyhq/code/wbap-api/src/db/client.ts`
- Create: `/Users/qwertyhq/code/wbap-api/src/db/schema.ts`
- Create: `/Users/qwertyhq/code/wbap-api/src/db/migrate.ts`
- Create: `/Users/qwertyhq/code/wbap-api/drizzle/0000_init_schemas.sql`

- [ ] **Step 11.1: Install Drizzle and pg driver**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add drizzle-orm@^0.36 postgres@^3.4
pnpm add -D drizzle-kit@^0.28
```

- [ ] **Step 11.2: Create drizzle-kit config**

Write `/Users/qwertyhq/code/wbap-api/drizzle.config.ts`:

```typescript
import { defineConfig } from "drizzle-kit";

const url = process.env.DATABASE_URL ?? "postgres://wbap:wbap@localhost:5432/wbap_billing";

export default defineConfig({
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url },
  strict: true,
  verbose: true,
  schemaFilter: ["auth", "core", "billing", "spool", "wallet", "audit", "migration"],
});
```

- [ ] **Step 11.3: Stub schema file**

Write `/Users/qwertyhq/code/wbap-api/src/db/schema.ts`:

```typescript
import { pgSchema, text, timestamp } from "drizzle-orm/pg-core";

// Phase 0 marker tables. Real domain tables ship in Phase 1+.
export const migrationSchema = pgSchema("migration");

export const schemaVersion = migrationSchema.table("schema_version", {
  id: text("id").primaryKey(),
  appliedAt: timestamp("applied_at", { withTimezone: true }).defaultNow().notNull(),
});
```

- [ ] **Step 11.4: Hand-write the first migration**

Write `/Users/qwertyhq/code/wbap-api/drizzle/0000_init_schemas.sql`:

```sql
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS spool;
CREATE SCHEMA IF NOT EXISTS wallet;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS migration;

CREATE TABLE IF NOT EXISTS migration.schema_version (
  id           text PRIMARY KEY,
  applied_at   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO migration.schema_version (id) VALUES ('0000_init_schemas')
  ON CONFLICT (id) DO NOTHING;
```

- [ ] **Step 11.5: Create db client factory**

Write `/Users/qwertyhq/code/wbap-api/src/db/client.ts`:

```typescript
import postgres from "postgres";
import { drizzle } from "drizzle-orm/postgres-js";
import * as schema from "@/db/schema";

export type Db = ReturnType<typeof createDb>["db"];

export function createDb(databaseUrl: string): {
  db: ReturnType<typeof drizzle<typeof schema>>;
  close: () => Promise<void>;
} {
  const sql = postgres(databaseUrl, { max: 10, idle_timeout: 30 });
  const db = drizzle(sql, { schema });
  return { db, close: () => sql.end({ timeout: 5 }) };
}
```

- [ ] **Step 11.6: Create migration runner**

Write `/Users/qwertyhq/code/wbap-api/src/db/migrate.ts`:

```typescript
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import postgres from "postgres";
import { loadConfig } from "@/config";
import { createLogger } from "@/observability/logger";

async function run(): Promise<void> {
  const cfg = loadConfig();
  const log = createLogger(cfg);
  const sql = postgres(cfg.databaseUrl, { max: 1 });

  try {
    await sql`CREATE SCHEMA IF NOT EXISTS migration`;
    await sql`CREATE TABLE IF NOT EXISTS migration.schema_version (
      id text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`;

    const dir = join(process.cwd(), "drizzle");
    const files = readdirSync(dir)
      .filter((f) => f.endsWith(".sql"))
      .sort();

    for (const file of files) {
      const id = file.replace(/\.sql$/, "");
      const applied = await sql<{ id: string }[]>`
        SELECT id FROM migration.schema_version WHERE id = ${id}
      `;
      if (applied.length > 0) {
        log.info({ id }, "migration already applied, skipping");
        continue;
      }
      const sqlText = readFileSync(join(dir, file), "utf8");
      log.info({ id }, "applying migration");
      await sql.unsafe(sqlText);
    }
    log.info("migrations complete");
  } finally {
    await sql.end({ timeout: 5 });
  }
}

run().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error("migration failed", err);
  process.exit(1);
});
```

- [ ] **Step 11.7: Run migrations against the dev container**

```bash
cd /Users/qwertyhq/code/wbap-api
NODE_ENV=development PORT=8080 \
  DATABASE_URL=postgres://wbap:wbap@localhost:5432/wbap_billing \
  REDIS_URL=redis://localhost:6379 \
  pnpm db:migrate
```

Expected: log lines `applying migration`, then `migrations complete`. Re-running prints `already applied`.

- [ ] **Step 11.8: Verify schemas exist**

```bash
docker exec wbap-api-postgres psql -U wbap -d wbap_billing -c "\dn"
docker exec wbap-api-postgres psql -U wbap -d wbap_billing -c "SELECT id, applied_at FROM migration.schema_version"
```

Expected: lists schemas auth/core/billing/spool/wallet/audit/migration; `0000_init_schemas` row present.

- [ ] **Step 11.9: Commit**

```bash
git add drizzle.config.ts drizzle/0000_init_schemas.sql src/db/client.ts src/db/schema.ts src/db/migrate.ts package.json pnpm-lock.yaml
git commit -m "feat(db): add drizzle setup and 0000_init_schemas migration"
```

---

## Task 12: Integration test for DB connection (testcontainers)

**Files:**
- Modify: `/Users/qwertyhq/code/wbap-api/tests/setup.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/integration/db.test.ts`

- [ ] **Step 12.1: Install testcontainers**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add -D @testcontainers/postgresql@^10 testcontainers@^10
```

- [ ] **Step 12.2: Write failing integration test**

Write `/Users/qwertyhq/code/wbap-api/tests/integration/db.test.ts`:

```typescript
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { PostgreSqlContainer, type StartedPostgreSqlContainer } from "@testcontainers/postgresql";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import postgres from "postgres";
import { createDb } from "@/db/client";

describe("db client", () => {
  let container: StartedPostgreSqlContainer;
  let url: string;

  beforeAll(async () => {
    container = await new PostgreSqlContainer("postgres:16-alpine")
      .withDatabase("wbap_billing")
      .withUsername("wbap")
      .withPassword("wbap")
      .start();
    url = container.getConnectionUri();

    const sql = postgres(url, { max: 1 });
    const migration = readFileSync(
      join(process.cwd(), "drizzle", "0000_init_schemas.sql"),
      "utf8",
    );
    await sql.unsafe(migration);
    await sql.end({ timeout: 5 });
  }, 120_000);

  afterAll(async () => {
    await container?.stop();
  });

  it("connects and runs a trivial query", async () => {
    const { db, close } = createDb(url);
    try {
      const rows = await db.execute(`SELECT 1 AS one`);
      expect(rows[0]).toEqual({ one: 1 });
    } finally {
      await close();
    }
  });

  it("has all expected schemas after migration", async () => {
    const sql = postgres(url, { max: 1 });
    try {
      const rows = await sql<{ schema_name: string }[]>`
        SELECT schema_name FROM information_schema.schemata
        WHERE schema_name IN ('auth','core','billing','spool','wallet','audit','migration')
        ORDER BY schema_name
      `;
      const names = rows.map((r) => r.schema_name);
      expect(names).toEqual(["audit", "auth", "billing", "core", "migration", "spool", "wallet"]);
    } finally {
      await sql.end({ timeout: 5 });
    }
  });

  it("records the migration in schema_version", async () => {
    const sql = postgres(url, { max: 1 });
    try {
      const rows = await sql<{ id: string }[]>`
        SELECT id FROM migration.schema_version WHERE id = '0000_init_schemas'
      `;
      expect(rows.length).toBe(1);
    } finally {
      await sql.end({ timeout: 5 });
    }
  });
});
```

- [ ] **Step 12.3: Run failing/working test**

```bash
pnpm test tests/integration/db.test.ts
```

Expected: tests pass (Docker daemon must be running).

- [ ] **Step 12.4: Commit**

```bash
git add tests/integration/db.test.ts package.json pnpm-lock.yaml
git commit -m "test(db): add testcontainers integration test for connection and schemas"
```

---

## Task 13: Redis client + readiness probe wiring

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/redis/client.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/integration/redis.test.ts`
- Modify: `/Users/qwertyhq/code/wbap-api/src/server.ts`

- [ ] **Step 13.1: Install ioredis**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add ioredis@^5
```

- [ ] **Step 13.2: Write failing redis test**

Write `/Users/qwertyhq/code/wbap-api/tests/integration/redis.test.ts`:

```typescript
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { GenericContainer, type StartedTestContainer } from "testcontainers";
import { createRedis } from "@/redis/client";

describe("redis client", () => {
  let container: StartedTestContainer;
  let url: string;

  beforeAll(async () => {
    container = await new GenericContainer("redis:7-alpine")
      .withExposedPorts(6379)
      .start();
    url = `redis://${container.getHost()}:${container.getMappedPort(6379)}`;
  }, 120_000);

  afterAll(async () => {
    await container?.stop();
  });

  it("ping returns PONG", async () => {
    const { redis, close } = createRedis(url);
    try {
      const reply = await redis.ping();
      expect(reply).toBe("PONG");
    } finally {
      await close();
    }
  });

  it("set/get roundtrip works", async () => {
    const { redis, close } = createRedis(url);
    try {
      await redis.set("hello", "world");
      const got = await redis.get("hello");
      expect(got).toBe("world");
    } finally {
      await close();
    }
  });
});
```

- [ ] **Step 13.3: Run failing test**

```bash
pnpm test tests/integration/redis.test.ts
```

Expected: fails (createRedis not found).

- [ ] **Step 13.4: Implement redis client**

Write `/Users/qwertyhq/code/wbap-api/src/redis/client.ts`:

```typescript
import Redis from "ioredis";

export function createRedis(url: string): {
  redis: Redis;
  close: () => Promise<void>;
} {
  const redis = new Redis(url, {
    maxRetriesPerRequest: 3,
    enableReadyCheck: true,
    lazyConnect: false,
  });
  return { redis, close: () => redis.quit().then(() => undefined) };
}
```

- [ ] **Step 13.5: Run redis tests**

```bash
pnpm test tests/integration/redis.test.ts
```

Expected: tests pass.

- [ ] **Step 13.6: Wire DB + Redis probes into server.ts**

Replace `/Users/qwertyhq/code/wbap-api/src/server.ts`:

```typescript
import { serve } from "@hono/node-server";
import { loadConfig } from "@/config";
import { createApp } from "@/app";
import { createLogger } from "@/observability/logger";
import { createDb } from "@/db/client";
import { createRedis } from "@/redis/client";

async function main(): Promise<void> {
  const cfg = loadConfig();
  const log = createLogger(cfg);

  const { db, close: closeDb } = createDb(cfg.databaseUrl);
  const { redis, close: closeRedis } = createRedis(cfg.redisUrl);

  const app = createApp({
    probes: {
      db: async () => {
        await db.execute(`SELECT 1`);
        return true;
      },
      redis: async () => {
        const reply = await redis.ping();
        return reply === "PONG";
      },
    },
  });

  const server = serve({ fetch: app.fetch, port: cfg.port }, ({ port }) => {
    log.info({ port, nodeEnv: cfg.nodeEnv }, "wbap-api started");
  });

  const shutdown = async (signal: string): Promise<void> => {
    log.info({ signal }, "shutting down");
    server.close();
    await closeRedis();
    await closeDb();
    process.exit(0);
  };

  process.on("SIGTERM", () => void shutdown("SIGTERM"));
  process.on("SIGINT", () => void shutdown("SIGINT"));
}

main().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error("boot failure", err);
  process.exit(1);
});
```

- [ ] **Step 13.7: Verify end-to-end with the dev stack**

```bash
cd /Users/qwertyhq/code/wbap-api
docker compose -f docker/docker-compose.dev.yml up -d
NODE_ENV=development PORT=8080 \
  DATABASE_URL=postgres://wbap:wbap@localhost:5432/wbap_billing \
  REDIS_URL=redis://localhost:6379 \
  pnpm dev &
sleep 3
curl -s http://localhost:8080/ready | jq
kill %1
```

Expected output:
```json
{"status":"ok","checks":{"db":"ok","redis":"ok"}}
```

- [ ] **Step 13.8: Commit**

```bash
git add src/redis/client.ts tests/integration/redis.test.ts src/server.ts package.json pnpm-lock.yaml
git commit -m "feat(redis): add ioredis client and wire readiness probes"
```

---

## Task 14: Prometheus metrics endpoint (TDD)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/observability/metrics.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/integration/metrics.test.ts`
- Modify: `/Users/qwertyhq/code/wbap-api/src/app.ts`

- [ ] **Step 14.1: Install prom-client**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add prom-client@^15
```

- [ ] **Step 14.2: Write failing test**

Write `/Users/qwertyhq/code/wbap-api/tests/integration/metrics.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { Hono } from "hono";
import { createMetrics, metricsMiddleware, metricsRoute } from "@/observability/metrics";

describe("/metrics", () => {
  it("exposes prometheus exposition format with default metrics", async () => {
    const m = createMetrics();
    const app = new Hono().route("/", metricsRoute(m));
    const res = await app.request("/metrics");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toMatch(/text\/plain/);
    const body = await res.text();
    expect(body).toMatch(/process_cpu_user_seconds_total/);
  });

  it("counts http requests via middleware label", async () => {
    const m = createMetrics();
    const app = new Hono()
      .use("*", metricsMiddleware(m))
      .get("/foo", (c) => c.text("ok"))
      .route("/", metricsRoute(m));

    await app.request("/foo");
    await app.request("/foo");

    const res = await app.request("/metrics");
    const body = await res.text();
    expect(body).toMatch(/wbap_api_http_requests_total\{[^}]*route="\/foo"[^}]*\} 2/);
  });
});
```

- [ ] **Step 14.3: Run failing test**

```bash
pnpm test tests/integration/metrics.test.ts
```

Expected: fails.

- [ ] **Step 14.4: Implement metrics module**

Write `/Users/qwertyhq/code/wbap-api/src/observability/metrics.ts`:

```typescript
import { Hono } from "hono";
import type { MiddlewareHandler } from "hono";
import { collectDefaultMetrics, Counter, Histogram, Registry } from "prom-client";

export type Metrics = {
  registry: Registry;
  httpRequestsTotal: Counter<"method" | "route" | "status">;
  httpRequestDurationSeconds: Histogram<"method" | "route" | "status">;
};

export function createMetrics(): Metrics {
  const registry = new Registry();
  collectDefaultMetrics({ register: registry });

  const httpRequestsTotal = new Counter({
    name: "wbap_api_http_requests_total",
    help: "Total HTTP requests handled by wbap-api",
    labelNames: ["method", "route", "status"] as const,
    registers: [registry],
  });

  const httpRequestDurationSeconds = new Histogram({
    name: "wbap_api_http_request_duration_seconds",
    help: "HTTP request duration",
    labelNames: ["method", "route", "status"] as const,
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [registry],
  });

  return { registry, httpRequestsTotal, httpRequestDurationSeconds };
}

export function metricsMiddleware(m: Metrics): MiddlewareHandler {
  return async (c, next) => {
    const start = process.hrtime.bigint();
    await next();
    const elapsedSec = Number(process.hrtime.bigint() - start) / 1e9;
    const route = c.req.routePath ?? c.req.path;
    const labels = {
      method: c.req.method,
      route,
      status: String(c.res.status),
    };
    m.httpRequestsTotal.inc(labels);
    m.httpRequestDurationSeconds.observe(labels, elapsedSec);
  };
}

export function metricsRoute(m: Metrics): Hono {
  const app = new Hono();
  app.get("/metrics", async (c) => {
    const body = await m.registry.metrics();
    return c.text(body, 200, { "Content-Type": m.registry.contentType });
  });
  return app;
}
```

- [ ] **Step 14.5: Wire metrics into app.ts**

Replace `/Users/qwertyhq/code/wbap-api/src/app.ts`:

```typescript
import { Hono } from "hono";
import { requestId } from "@/middleware/request-id";
import { errorHandler } from "@/middleware/error-handler";
import { helloRoute } from "@/routes/hello";
import { healthRoute } from "@/routes/health";
import { readyRoute, type ReadinessProbes } from "@/routes/ready";
import {
  createMetrics,
  metricsMiddleware,
  metricsRoute,
  type Metrics,
} from "@/observability/metrics";

export type AppDeps = {
  probes: ReadinessProbes;
  metrics?: Metrics;
};

export function createApp(deps: AppDeps): Hono {
  const metrics = deps.metrics ?? createMetrics();
  const app = new Hono();
  app.use("*", requestId());
  app.use("*", metricsMiddleware(metrics));
  app.onError(errorHandler());
  app.route("/", healthRoute());
  app.route("/", readyRoute(deps.probes));
  app.route("/", helloRoute());
  app.route("/", metricsRoute(metrics));
  return app;
}
```

- [ ] **Step 14.6: Run all tests**

```bash
pnpm test
```

Expected: all green.

- [ ] **Step 14.7: Commit**

```bash
git add src/observability/metrics.ts src/app.ts tests/integration/metrics.test.ts package.json pnpm-lock.yaml
git commit -m "feat(observability): add /metrics with prom-client and HTTP middleware"
```

---

## Task 15: OpenTelemetry tracing scaffold (no-op exporter by default)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/src/observability/tracing.ts`
- Modify: `/Users/qwertyhq/code/wbap-api/src/server.ts`
- Create: `/Users/qwertyhq/code/wbap-api/tests/unit/tracing.test.ts`

- [ ] **Step 15.1: Install OTel SDK**

```bash
cd /Users/qwertyhq/code/wbap-api
pnpm add @opentelemetry/sdk-node@^0.55 @opentelemetry/auto-instrumentations-node@^0.51 @opentelemetry/exporter-trace-otlp-http@^0.55 @opentelemetry/resources@^1 @opentelemetry/semantic-conventions@^1
```

- [ ] **Step 15.2: Write failing test**

Write `/Users/qwertyhq/code/wbap-api/tests/unit/tracing.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { initTracing } from "@/observability/tracing";

describe("initTracing", () => {
  it("is a no-op when OTEL_EXPORTER_OTLP_ENDPOINT is unset", () => {
    delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
    const result = initTracing({ serviceName: "wbap-api-test" });
    expect(result.enabled).toBe(false);
  });

  it("is enabled when OTEL_EXPORTER_OTLP_ENDPOINT is set", () => {
    process.env.OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4318";
    try {
      const result = initTracing({ serviceName: "wbap-api-test" });
      expect(result.enabled).toBe(true);
      expect(typeof result.shutdown).toBe("function");
    } finally {
      delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
    }
  });
});
```

- [ ] **Step 15.3: Run failing test**

```bash
pnpm test tests/unit/tracing.test.ts
```

Expected: fails (initTracing not found).

- [ ] **Step 15.4: Implement tracing init**

Write `/Users/qwertyhq/code/wbap-api/src/observability/tracing.ts`:

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { Resource } from "@opentelemetry/resources";
import { ATTR_SERVICE_NAME } from "@opentelemetry/semantic-conventions";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";

export type TracingResult =
  | { enabled: false }
  | { enabled: true; shutdown: () => Promise<void> };

export function initTracing(opts: { serviceName: string }): TracingResult {
  const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  if (!endpoint) return { enabled: false };

  const sdk = new NodeSDK({
    resource: new Resource({ [ATTR_SERVICE_NAME]: opts.serviceName }),
    traceExporter: new OTLPTraceExporter({ url: `${endpoint}/v1/traces` }),
    instrumentations: [getNodeAutoInstrumentations()],
  });
  sdk.start();
  return { enabled: true, shutdown: () => sdk.shutdown() };
}
```

- [ ] **Step 15.5: Wire into server.ts**

In `/Users/qwertyhq/code/wbap-api/src/server.ts`, add after `loadConfig` and before `createDb`:

```typescript
import { initTracing } from "@/observability/tracing";
// ...
const tracing = initTracing({ serviceName: "wbap-api" });
```

And in the `shutdown` function, add before `closeRedis`:

```typescript
if (tracing.enabled) {
  await tracing.shutdown();
}
```

(Apply both edits to the existing file.)

- [ ] **Step 15.6: Run all tests + typecheck**

```bash
pnpm test
pnpm typecheck
```

Expected: all green.

- [ ] **Step 15.7: Commit**

```bash
git add src/observability/tracing.ts src/server.ts tests/unit/tracing.test.ts package.json pnpm-lock.yaml
git commit -m "feat(observability): add OTel tracing scaffold (off by default)"
```

---

## Task 16: Distroless production Dockerfile

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/docker/Dockerfile`
- Create: `/Users/qwertyhq/code/wbap-api/.dockerignore`

- [ ] **Step 16.1: Write `.dockerignore`**

Write `/Users/qwertyhq/code/wbap-api/.dockerignore`:

```
node_modules
dist
coverage
.git
.github
.vscode
tests
*.md
docker-compose*.yml
.env
.env.*
!.env.example
```

- [ ] **Step 16.2: Write Dockerfile**

Write `/Users/qwertyhq/code/wbap-api/docker/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1.7

# ----- Stage 1: deps (dev+prod) -----
FROM node:20.18-alpine AS deps
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.15.0 --activate
COPY package.json pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile

# ----- Stage 2: build -----
FROM node:20.18-alpine AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@10.15.0 --activate
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm run build
# Prune devDeps for the runtime layer
RUN --mount=type=cache,id=pnpm-store,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --prod --ignore-scripts

# ----- Stage 3: runtime (distroless) -----
FROM gcr.io/distroless/nodejs20-debian12:nonroot AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/drizzle ./drizzle
COPY --from=build /app/package.json ./package.json
USER nonroot
EXPOSE 8080
CMD ["dist/server.js"]
```

- [ ] **Step 16.3: Build the image**

```bash
cd /Users/qwertyhq/code/wbap-api
docker build -f docker/Dockerfile -t wbap-api:phase0 .
```

Expected: build succeeds, three stages.

- [ ] **Step 16.4: Smoke-run the image against dev stack**

```bash
docker run --rm -d --name wbap-api-smoke \
  --network host \
  -e NODE_ENV=production \
  -e PORT=8080 \
  -e DATABASE_URL=postgres://wbap:wbap@localhost:5432/wbap_billing \
  -e REDIS_URL=redis://localhost:6379 \
  -e LOG_LEVEL=info \
  wbap-api:phase0
sleep 2
curl -s http://localhost:8080/health
curl -s http://localhost:8080/ready
docker stop wbap-api-smoke
```

Expected:
- /health → `{"status":"ok"}`
- /ready → `{"status":"ok","checks":{"db":"ok","redis":"ok"}}`.

- [ ] **Step 16.5: Verify image size and user**

```bash
docker image inspect wbap-api:phase0 --format '{{.Config.User}}'
docker image ls wbap-api:phase0
```

Expected: User is `nonroot` (or its numeric UID), image under ~250 MB.

- [ ] **Step 16.6: Commit**

```bash
git add docker/Dockerfile .dockerignore
git commit -m "build(docker): add distroless production image"
```

---

## Task 17: GitHub Actions CI with security gates

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/.github/workflows/ci.yml`

- [ ] **Step 17.1: Write workflow**

Write `/Users/qwertyhq/code/wbap-api/.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  security-events: write
  pull-requests: read

concurrency:
  group: ci-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  static:
    name: Lint + Typecheck + Format
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 10.15.0
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm format:check
      - run: pnpm lint
      - run: pnpm typecheck

  test:
    name: Tests (with testcontainers)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 10.15.0
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm test
        env:
          NODE_OPTIONS: --max-old-space-size=4096
      - name: Upload coverage
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage
          if-no-files-found: ignore

  audit:
    name: npm audit (high+ severity)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 10.15.0
      - uses: actions/setup-node@v4
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm audit --prod --audit-level=high

  semgrep:
    name: Semgrep SAST
    runs-on: ubuntu-latest
    container:
      image: returntocorp/semgrep:latest
    steps:
      - uses: actions/checkout@v4
      - run: semgrep ci --config=p/typescript --config=p/owasp-top-ten --config=p/secrets --error
        env:
          SEMGREP_RULES: ""

  build-image:
    name: Build distroless image
    runs-on: ubuntu-latest
    needs: [static, test, audit, semgrep]
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - name: Build (no push)
        uses: docker/build-push-action@v6
        with:
          context: .
          file: docker/Dockerfile
          tags: wbap-api:ci-${{ github.sha }}
          push: false
          load: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
      - name: Trivy scan (filesystem + image)
        uses: aquasecurity/trivy-action@0.24.0
        with:
          image-ref: wbap-api:ci-${{ github.sha }}
          severity: HIGH,CRITICAL
          exit-code: "1"
          ignore-unfixed: true
          format: table
```

- [ ] **Step 17.2: Validate YAML locally (best-effort)**

```bash
cd /Users/qwertyhq/code/wbap-api
node -e "import('js-yaml').then(y => console.log(JSON.stringify(y.default.load(require('node:fs').readFileSync('.github/workflows/ci.yml','utf8'))).length))" 2>&1 || echo "skip if js-yaml not installed"
```

Expected: numeric length printed (or skip notice). Actual workflow validation runs in GitHub.

- [ ] **Step 17.3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add lint+typecheck+test+audit+semgrep+trivy pipeline"
```

---

## Task 18: Caddyfile reverse-proxy (default 100% to SHM)

**Files:**
- Create: `/Users/qwertyhq/code/wbap-api/caddy/Caddyfile`
- Create: `/Users/qwertyhq/code/wbap-api/caddy/README.md`

- [ ] **Step 18.1: Write Caddyfile**

Write `/Users/qwertyhq/code/wbap-api/caddy/Caddyfile`:

```caddy
# Caddy reverse-proxy for wbap.
#
# Phase 0: 100% of traffic is forwarded to the existing SHM upstream.
# Subsequent phases will introduce per-route handle blocks that route
# to the new wbap-api upstream behind a feature flag.
#
# Upstreams are read from environment variables; provide them via the
# Caddy container's env. SHM_UPSTREAM is required; WBAP_API_UPSTREAM
# is consumed by stub blocks added in later phases (kept here so reviewers
# can spot the wiring before code lands).
{
	admin off
	auto_https off
	persist_config off
}

(common_security_headers) {
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options    "nosniff"
		X-Frame-Options           "DENY"
		Referrer-Policy           "strict-origin-when-cross-origin"
		-Server
	}
}

:80 {
	import common_security_headers
	encode zstd gzip

	# Phase 0: every request goes to SHM. The wbap-api upstream block
	# below stays commented out until Phase 4+ flips routes via feature
	# flags managed in PG-billing migration.feature_flags.
	#
	# handle /health-wbap-api {
	#   reverse_proxy {$WBAP_API_UPSTREAM}
	# }

	reverse_proxy {$SHM_UPSTREAM} {
		header_up X-Forwarded-Proto {scheme}
		header_up X-Forwarded-Host  {host}
		header_up X-Real-IP         {remote_host}
	}
}
```

- [ ] **Step 18.2: Write Caddy README**

Write `/Users/qwertyhq/code/wbap-api/caddy/README.md`:

```markdown
# Caddy reverse-proxy

Routes wbap traffic. In Phase 0, sends 100% to SHM. Per-route flags will
be added in later phases that route `/auth/*`, `/services/*`, etc. to the
new `wbap-api` upstream once they're ported.

## Required env

- `SHM_UPSTREAM` — host:port of the running SHM API (e.g. `shm:8080`).
- `WBAP_API_UPSTREAM` — host:port of wbap-api (used in later phases).

## Local sanity

\`\`\`bash
docker run --rm -p 8081:80 \
  -e SHM_UPSTREAM=httpbin.org \
  -v "$PWD/Caddyfile":/etc/caddy/Caddyfile:ro \
  caddy:2
\`\`\`

Then `curl -H 'Host: example' http://localhost:8081/get` should reach httpbin.
```

- [ ] **Step 18.3: Validate Caddyfile syntax**

```bash
cd /Users/qwertyhq/code/wbap-api
docker run --rm -v "$PWD/caddy/Caddyfile":/etc/caddy/Caddyfile:ro \
  caddy:2 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

Expected: `Valid configuration` printed. (May warn about missing env vars at parse time — that's acceptable; runtime substitution happens at start.)

- [ ] **Step 18.4: Commit**

```bash
git add caddy/Caddyfile caddy/README.md
git commit -m "feat(caddy): add reverse-proxy config defaulting 100% to SHM"
```

---

## Task 19: Final exit-criteria verification

This task confirms the spec's Phase 0 exit criteria: hello-world via wbap-api, PG reachable, observability wired.

**Files:**
- Modify: `/Users/qwertyhq/code/wbap-api/README.md` (add verification section)

- [ ] **Step 19.1: Bring up the dev stack**

```bash
cd /Users/qwertyhq/code/wbap-api
docker compose -f docker/docker-compose.dev.yml up -d
sleep 5
```

- [ ] **Step 19.2: Run migrations**

```bash
NODE_ENV=development PORT=8080 \
  DATABASE_URL=postgres://wbap:wbap@localhost:5432/wbap_billing \
  REDIS_URL=redis://localhost:6379 \
  LOG_LEVEL=info \
  pnpm db:migrate
```

Expected: `migrations complete` log line.

- [ ] **Step 19.3: Start the server**

```bash
NODE_ENV=development PORT=8080 \
  DATABASE_URL=postgres://wbap:wbap@localhost:5432/wbap_billing \
  REDIS_URL=redis://localhost:6379 \
  LOG_LEVEL=info \
  pnpm dev &
sleep 3
```

- [ ] **Step 19.4: Verify hello-world**

```bash
curl -s http://localhost:8080/hello?name=phase0
```

Expected: `{"greeting":"hello, phase0"}`.

- [ ] **Step 19.5: Verify health/ready**

```bash
curl -s http://localhost:8080/health
curl -s http://localhost:8080/ready
```

Expected:
- `{"status":"ok"}`
- `{"status":"ok","checks":{"db":"ok","redis":"ok"}}`

- [ ] **Step 19.6: Verify metrics**

```bash
curl -s http://localhost:8080/metrics | head -30
```

Expected: prometheus exposition format containing `wbap_api_http_requests_total` counters and `process_cpu_user_seconds_total`.

- [ ] **Step 19.7: Stop the dev server**

```bash
kill %1
```

- [ ] **Step 19.8: Run full quality suite**

```bash
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
```

Expected: all four exit 0.

- [ ] **Step 19.9: Update README with verified quickstart**

Replace the README quickstart section with this verified content. Open `/Users/qwertyhq/code/wbap-api/README.md` and replace its entire contents:

```markdown
# wbap-api

New TypeScript backend replacing SHM. See design spec at the SHM repo:
`docs/superpowers/specs/2026-05-07-shm-replacement-design.md`.

## Status

Phase 0 (Foundation) complete. Skeleton service runs, migrations apply,
metrics export, distroless image builds, CI is wired.

## Requirements

- Docker + Docker Compose v2
- Node 20 LTS (`.nvmrc` pinned)
- pnpm 10

## Quickstart

\`\`\`bash
pnpm install
docker compose -f docker/docker-compose.dev.yml up -d
cp .env.example .env
pnpm db:migrate
pnpm dev
\`\`\`

Then in another terminal:

\`\`\`bash
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/hello?name=phase0
curl http://localhost:8080/metrics | head -30
\`\`\`

## Scripts

| Script | What |
|--------|------|
| pnpm dev          | Start with tsx watch |
| pnpm build        | TypeScript build to dist/ |
| pnpm start        | Run dist/server.js |
| pnpm test         | Vitest run (unit + integration with testcontainers) |
| pnpm lint         | ESLint |
| pnpm format       | Prettier write |
| pnpm typecheck    | tsc --noEmit |
| pnpm db:migrate   | Apply pending SQL migrations |
| pnpm db:generate  | drizzle-kit generate |
| pnpm db:studio    | drizzle-kit studio |

## Layout

See module boundaries described in
`docs/superpowers/plans/2026-05-07-phase-0-foundation.md`.

## Phase 0 exit criteria

- ✅ hello-world endpoint reachable via wbap-api
- ✅ PG-billing instance reachable, schemas + version table created
- ✅ observability wired: logs (pino), metrics (/metrics), tracing (OTel SDK off-by-default)
- ✅ distroless image builds and runs with /ready=ok
- ✅ CI runs lint, typecheck, tests, npm audit, semgrep, trivy
- ✅ Caddy reverse-proxy defaults to SHM upstream
```

- [ ] **Step 19.10: Tear down the dev stack**

```bash
docker compose -f docker/docker-compose.dev.yml down
```

- [ ] **Step 19.11: Commit and tag the milestone**

```bash
git add README.md
git commit -m "docs: complete README with Phase 0 verified quickstart"
git tag -a v0.0.0-phase0 -m "Phase 0 (Foundation) complete"
```

---

## Spec coverage cross-check

| Spec section | Plan tasks |
|--------------|------------|
| §3.1 Topology — wbap-api skeleton | Tasks 1-9, 13 |
| §3.1 Topology — Caddy reverse proxy | Task 18 |
| §3.2 Data stores — PG instance | Tasks 10-12 |
| §3.2 Data stores — Redis | Tasks 10, 13 |
| §3.3 Stack: Node 20, Hono, Drizzle, Zod, pino, prom-client, OTel, Vitest, testcontainers, distroless | Tasks 1-17 |
| §5.5 Phase 0 exit criteria — hello-world reachable | Tasks 7, 19 |
| §5.5 Phase 0 exit criteria — PG reachable | Tasks 10-12, 19 |
| §5.5 Phase 0 exit criteria — observability working | Tasks 5, 14, 15, 19 |
| §8 Deployment — distroless image, multi-stage | Task 16 |
| §8 Deployment — CI: lint, typecheck, test, semgrep, npm audit, trivy | Task 17 |
| §3.5 Auth, §3.4 Wallet, §4 Data model schemas | Out of Phase 0 — covered in subsequent phase plans |

Open spec items (§10 Open Questions) remain open and will be addressed in their respective subsequent phase plans:

- TZ verification (§10.1) → Phase 1 (CDC bring-up)
- Composite-services audit (§10.2) → Phase 4 (read endpoints)
- Roulette feature decision (§10.3) → Phase 7 (users write-path)
- Argon2id final params (§10.4) → Phase 1 or auth-roll-out plan
- SOPS / age key custody (§10.5) → before first prod deploy
- PG instance host topology (§10.6) → Phase 1 setup
- Pay-system callback URL audit (§10.7) → Phase 6
- bonus_history sign semantics (§10.8) → Phase 1 (wallet bootstrap)
