# Phase 6 Hardening Sprint (5 Phases)

**Framework:** OWASP API Security Top 10 2023 + Cloudflare Workers Best Practices
**Duration:** 4-6 hours (proof-driven, test-first approach)
**Goal:** Eliminate threats, prove correctness, simplify Phase 6 implementation

**Philosophy:** Less documentation, more proofs. Every threat gets a test vector. Every API gets a golden path. When this sprint is done, Phase 6 implementation should feel **obvious and safe**.

---

## Phase 1: Authentication Hardening (60 min)

**Threat:** API1:2023 Broken Object Level Authorization
**Goal:** Prove Firebase Auth works, lock down all endpoints

### 1.1: Install Firebase Auth Library (10 min)

```bash
cd buds-relay
npm install firebase-auth-cloudflare-workers
```

**Why this library:**
- Zero dependencies (Web Standard APIs only)
- KV-backed public key caching
- Battle-tested (used in production)

**Sources:**
- [firebase-auth-cloudflare-workers on npm](https://www.npmjs.com/package/firebase-auth-cloudflare-workers)
- [GitHub: Code-Hex/firebase-auth-cloudflare-workers](https://github.com/Code-Hex/firebase-auth-cloudflare-workers)

### 1.2: Create Auth Middleware (20 min)

**File:** `src/middleware/auth.ts`

```typescript
import { Auth, WorkersKVStoreSingle } from 'firebase-auth-cloudflare-workers';
import { Context, Next } from 'hono';

export interface AuthEnv {
  FIREBASE_PROJECT_ID: string;
  KV_CACHE: KVNamespace;
}

let authInstance: Auth | null = null;

function getAuth(env: AuthEnv): Auth {
  if (!authInstance) {
    const kvStore = new WorkersKVStoreSingle(env.KV_CACHE);
    authInstance = Auth.getOrInitialize(env.FIREBASE_PROJECT_ID, kvStore);
  }
  return authInstance;
}

export async function requireAuth(c: Context<{ Bindings: AuthEnv }>, next: Next) {
  const authHeader = c.req.header('Authorization');

  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Unauthorized: Missing token' }, 401);
  }

  const token = authHeader.substring(7);

  try {
    const auth = getAuth(c.env);
    const decodedToken = await auth.verifyIdToken(token);

    // Store user info in context
    c.set('user', {
      uid: decodedToken.uid,
      phoneNumber: decodedToken.phone_number,
      email: decodedToken.email,
    });

    await next();
  } catch (error) {
    console.error('[AUTH] Token verification failed:', error);
    return c.json({ error: 'Unauthorized: Invalid token' }, 401);
  }
}
```

### 1.3: Add KV Namespace for Caching (5 min)

**File:** `wrangler.toml`

```toml
[[kv_namespaces]]
binding = "KV_CACHE"
id = "YOUR_KV_ID"  # Get from: wrangler kv:namespace create KV_CACHE

[vars]
FIREBASE_PROJECT_ID = "buds-prod"  # Replace with your project ID
```

**Create KV:**
```bash
wrangler kv:namespace create KV_CACHE
# Copy the ID to wrangler.toml
```

### 1.4: Golden Test Vector (25 min)

**File:** `test/auth.test.ts`

```typescript
import { describe, it, expect, beforeAll } from 'vitest';
import { requireAuth } from '../src/middleware/auth';
import { Context } from 'hono';

describe('Authentication Middleware', () => {
  let validToken: string;

  beforeAll(async () => {
    // Generate a valid Firebase token for testing
    // Use Firebase Admin SDK locally or save a test token
    validToken = process.env.TEST_FIREBASE_TOKEN || '';
  });

  it('GOLDEN: accepts valid Firebase token', async () => {
    const mockContext = {
      req: {
        header: (name: string) => name === 'Authorization' ? `Bearer ${validToken}` : null,
      },
      env: {
        FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID,
        KV_CACHE: mockKV,
      },
      set: vi.fn(),
      json: vi.fn(),
    } as any;

    const mockNext = vi.fn();

    await requireAuth(mockContext, mockNext);

    expect(mockNext).toHaveBeenCalled();
    expect(mockContext.set).toHaveBeenCalledWith('user', expect.objectContaining({
      uid: expect.any(String),
      phoneNumber: expect.any(String),
    }));
  });

  it('THREAT: rejects missing token', async () => {
    const mockContext = {
      req: { header: () => null },
      json: vi.fn((body, status) => ({ body, status })),
    } as any;

    const result = await requireAuth(mockContext, vi.fn());

    expect(result.status).toBe(401);
    expect(result.body.error).toContain('Missing token');
  });

  it('THREAT: rejects expired token', async () => {
    const expiredToken = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...'; // Expired token

    const mockContext = {
      req: { header: () => `Bearer ${expiredToken}` },
      env: { FIREBASE_PROJECT_ID: 'test', KV_CACHE: mockKV },
      json: vi.fn((body, status) => ({ body, status })),
    } as any;

    const result = await requireAuth(mockContext, vi.fn());

    expect(result.status).toBe(401);
    expect(result.body.error).toContain('Invalid token');
  });

  it('THREAT: rejects malformed token', async () => {
    const malformedToken = 'not.a.jwt';

    const mockContext = {
      req: { header: () => `Bearer ${malformedToken}` },
      env: { FIREBASE_PROJECT_ID: 'test', KV_CACHE: mockKV },
      json: vi.fn((body, status) => ({ body, status })),
    } as any;

    const result = await requireAuth(mockContext, vi.fn());

    expect(result.status).toBe(401);
  });
});
```

**Run tests:**
```bash
npm install -D vitest
npx vitest run
```

**SUCCESS CRITERIA:**
- ✅ All 4 tests pass (1 golden, 3 threats)
- ✅ Valid token → authenticated
- ✅ Invalid/missing/expired token → 401

---

## Phase 2: Rate Limiting (45 min)

**Threat:** API4:2023 Unrestricted Resource Consumption
**Goal:** Prevent DID enumeration, DoS attacks

### 2.1: Use Cloudflare Rate Limiting (Native) (20 min)

**Cloudflare Workers Rate Limiting is now GA** (September 2025)

**File:** `src/middleware/ratelimit.ts`

```typescript
import { Context, Next } from 'hono';

// Rate limit configuration
const RATE_LIMITS = {
  '/api/lookup/did': { limit: 20, period: 60 },      // 20 requests per minute
  '/api/devices/register': { limit: 5, period: 300 }, // 5 per 5 minutes
  '/api/messages/send': { limit: 100, period: 60 },  // 100 per minute
  '/api/messages/inbox': { limit: 200, period: 60 }, // 200 per minute (polling)
};

export async function rateLimitMiddleware(c: Context, next: Next) {
  const path = new URL(c.req.url).pathname;
  const config = RATE_LIMITS[path];

  if (!config) {
    return next(); // No rate limit for this path
  }

  // Use Cloudflare's native rate limiting binding
  const rateLimiter = c.env.RATE_LIMITER;
  const clientIP = c.req.header('CF-Connecting-IP') || 'unknown';
  const key = `${path}:${clientIP}`;

  try {
    const { success } = await rateLimiter.limit({ key });

    if (!success) {
      return c.json({
        error: 'Rate limit exceeded',
        retryAfter: config.period,
      }, 429);
    }

    await next();
  } catch (error) {
    console.error('[RATELIMIT] Error:', error);
    // Fail open (allow request on error)
    await next();
  }
}
```

**Configure in `wrangler.toml`:**

```toml
[[unsafe.bindings]]
name = "RATE_LIMITER"
type = "ratelimit"
namespace_id = "buds_relay_ratelimit"

# Per-endpoint limits
simple = { limit = 100, period = 60 }  # Default: 100/min
```

**Sources:**
- [Cloudflare Workers Rate Limiting (GA)](https://developers.cloudflare.com/changelog/2025-09-19-ratelimit-workers-ga/)
- [Rate Limiting Runtime API](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)

### 2.2: Alternative - KV-Based Rate Limiting (Fallback)

If native rate limiting not available:

```typescript
export async function kvRateLimitMiddleware(c: Context, next: Next) {
  const path = new URL(c.req.url).pathname;
  const config = RATE_LIMITS[path];

  if (!config) return next();

  const clientIP = c.req.header('CF-Connecting-IP') || 'unknown';
  const key = `ratelimit:${path}:${clientIP}`;
  const kv = c.env.RATE_LIMIT_KV;

  const count = await kv.get(key);
  const current = count ? parseInt(count) : 0;

  if (current >= config.limit) {
    return c.json({ error: 'Rate limit exceeded' }, 429);
  }

  // Increment counter with TTL
  await kv.put(key, (current + 1).toString(), {
    expirationTtl: config.period,
  });

  await next();
}
```

### 2.3: Golden Test Vector (15 min)

**File:** `test/ratelimit.test.ts`

```typescript
describe('Rate Limiting', () => {
  it('GOLDEN: allows requests under limit', async () => {
    const req = new Request('https://api.getbuds.app/api/lookup/did', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer valid-token',
        'CF-Connecting-IP': '1.2.3.4',
      },
    });

    for (let i = 0; i < 20; i++) {
      const response = await worker.fetch(req, env);
      expect(response.status).not.toBe(429); // Should not be rate limited
    }
  });

  it('THREAT: blocks requests over limit', async () => {
    const req = new Request('https://api.getbuds.app/api/lookup/did', {
      method: 'POST',
      headers: {
        'Authorization': 'Bearer valid-token',
        'CF-Connecting-IP': '1.2.3.5',
      },
    });

    // Make 21 requests (limit is 20)
    for (let i = 0; i < 21; i++) {
      const response = await worker.fetch(req, env);
      if (i < 20) {
        expect(response.status).not.toBe(429);
      } else {
        expect(response.status).toBe(429); // 21st request blocked
      }
    }
  });

  it('THREAT: rate limit resets after period', async () => {
    // Advance time by 60 seconds (mocked)
    vi.advanceTimersByTime(60000);

    const req = new Request('https://api.getbuds.app/api/lookup/did', {
      method: 'POST',
      headers: { 'CF-Connecting-IP': '1.2.3.6' },
    });

    const response = await worker.fetch(req, env);
    expect(response.status).not.toBe(429); // Should be allowed again
  });
});
```

**SUCCESS CRITERIA:**
- ✅ Requests under limit → allowed
- ✅ Requests over limit → 429
- ✅ Rate limit resets after period

### 2.4: Update Index to Use Middleware (10 min)

**File:** `src/index.ts`

```typescript
import { rateLimitMiddleware } from './middleware/ratelimit';
import { requireAuth } from './middleware/auth';

// Apply rate limiting globally
app.use('/*', rateLimitMiddleware);

// Apply auth to protected routes
app.use('/api/*', requireAuth);

// Health check (no auth required)
app.get('/health', (c) => c.json({ status: 'ok' }));
```

---

## Phase 3: Input Validation (50 min)

**Threat:** API3:2023 Broken Object Property Level Authorization + API8:2023 Security Misconfiguration
**Goal:** Zero tolerance for invalid inputs, prove validation works

### 3.1: Validation Helpers (20 min)

**File:** `src/utils/validation.ts`

```typescript
import { z } from 'zod';

// Zod schemas for strict validation
export const schemas = {
  did: z.string().regex(/^did:buds:[A-Za-z0-9]{1,44}$/, 'Invalid DID format'),

  deviceId: z.string().uuid('Invalid device ID format'),

  base64: z.string().regex(/^[A-Za-z0-9+/]+=*$/, 'Invalid base64 format').min(1),

  phoneHash: z.string().regex(/^[a-f0-9]{64}$/, 'Invalid phone hash (must be SHA-256 hex)'),

  phoneNumber: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Invalid E.164 phone number'),

  deviceName: z.string().min(1).max(100, 'Device name too long'),

  messageId: z.string().uuid('Invalid message ID'),

  cid: z.string().regex(/^bafy[a-z0-9]{50,60}$/, 'Invalid CID format'),

  dids: z.array(z.string().regex(/^did:buds:[A-Za-z0-9]{1,44}$/)).min(1).max(12, 'Max 12 DIDs'),
};

// Validation wrapper
export function validate<T>(schema: z.ZodSchema<T>, data: unknown): T {
  return schema.parse(data);
}

// Safe validation (returns null on error)
export function safeValidate<T>(schema: z.ZodSchema<T>, data: unknown): T | null {
  const result = schema.safeParse(data);
  return result.success ? result.data : null;
}
```

**Install Zod:**
```bash
npm install zod
```

### 3.2: Apply Validation to Handlers (20 min)

**File:** `src/handlers/devices.ts` (updated)

```typescript
import { validate, schemas } from '../utils/validation';

export async function registerDevice(c: Context) {
  try {
    const user = c.get('user'); // Set by requireAuth middleware
    const body = await c.req.json();

    // VALIDATE ALL INPUTS
    const validatedInput = validate(z.object({
      deviceId: schemas.deviceId,
      deviceName: schemas.deviceName,
      pubkeyX25519: schemas.base64,
      pubkeyEd25519: schemas.base64,
      ownerDID: schemas.did,
    }), body);

    // All inputs are now type-safe and validated
    const { deviceId, deviceName, pubkeyX25519, pubkeyEd25519, ownerDID } = validatedInput;

    // Hash phone from Firebase Auth (not from request body)
    const phoneHash = hashPhone(user.phoneNumber);

    // ... rest of implementation
  } catch (error) {
    if (error instanceof z.ZodError) {
      return c.json({
        error: 'Validation failed',
        details: error.errors.map(e => `${e.path.join('.')}: ${e.message}`),
      }, 400);
    }
    throw error;
  }
}
```

**Repeat for all handlers:**
- `lookupDID` - validate `phoneNumber`
- `getDevices` - validate `dids` array
- `sendMessage` - validate all message fields
- `getInbox` - validate `did` query param

### 3.3: Golden Test Vectors (10 min)

**File:** `test/validation.test.ts`

```typescript
import { validate, schemas } from '../src/utils/validation';

describe('Input Validation', () => {
  describe('DID validation', () => {
    it('GOLDEN: accepts valid DID', () => {
      const validDID = 'did:buds:5dGHK7P9mNqR8vZw3T';
      expect(() => validate(schemas.did, validDID)).not.toThrow();
    });

    it('THREAT: rejects malformed DID', () => {
      const invalidDIDs = [
        'did:buds:',                    // Empty identifier
        'did:buds:abc!@#',              // Invalid characters
        'did:web:example.com',          // Wrong method
        'did:buds:' + 'a'.repeat(100),  // Too long
        'not-a-did',                    // Missing prefix
      ];

      invalidDIDs.forEach(did => {
        expect(() => validate(schemas.did, did)).toThrow();
      });
    });
  });

  describe('Phone hash validation', () => {
    it('GOLDEN: accepts valid SHA-256 hash', () => {
      const validHash = 'a'.repeat(64); // SHA-256 is 64 hex chars
      expect(() => validate(schemas.phoneHash, validHash)).not.toThrow();
    });

    it('THREAT: rejects non-hex characters', () => {
      const invalidHash = 'g'.repeat(64); // 'g' is not hex
      expect(() => validate(schemas.phoneHash, invalidHash)).toThrow();
    });

    it('THREAT: rejects wrong length', () => {
      const shortHash = 'a'.repeat(32); // SHA-1 length
      expect(() => validate(schemas.phoneHash, shortHash)).toThrow();
    });
  });

  describe('SQL injection prevention', () => {
    it('THREAT: DID with SQL injection attempt', () => {
      const sqlInjection = "did:buds:abc'); DROP TABLE devices; --";
      expect(() => validate(schemas.did, sqlInjection)).toThrow();
    });

    it('THREAT: Device name with SQL injection', () => {
      const sqlInjection = "Alice's iPhone'; DELETE FROM devices WHERE '1'='1";
      // Should pass validation (single quotes allowed in names)
      // But SQL injection prevented by prepared statements
      expect(() => validate(schemas.deviceName, sqlInjection)).not.toThrow();
    });
  });
});
```

**SUCCESS CRITERIA:**
- ✅ All valid inputs pass
- ✅ All invalid inputs rejected
- ✅ SQL injection attempts caught

---

## Phase 4: Error Handling & Observability (40 min)

**Threat:** API9:2023 Improper Inventory Management
**Goal:** Safe errors, structured logging, zero info leaks

### 4.1: Error Handling System (15 min)

**File:** `src/utils/errors.ts`

```typescript
export class AppError extends Error {
  constructor(
    public message: string,
    public statusCode: number,
    public code: string,
    public internalDetails?: string
  ) {
    super(message);
    this.name = 'AppError';
  }
}

// Predefined errors
export const Errors = {
  Unauthorized: () => new AppError('Unauthorized', 401, 'AUTH_FAILED'),
  Forbidden: () => new AppError('Forbidden', 403, 'FORBIDDEN'),
  NotFound: (resource: string) => new AppError(`${resource} not found`, 404, 'NOT_FOUND'),
  RateLimited: () => new AppError('Rate limit exceeded', 429, 'RATE_LIMITED'),
  ValidationFailed: (details: string) => new AppError('Validation failed', 400, 'VALIDATION_ERROR', details),
  Internal: () => new AppError('Internal server error', 500, 'INTERNAL_ERROR'),
};

export function handleError(error: unknown, c: Context): Response {
  // Structured logging (safe for Cloudflare Workers logs)
  const requestId = c.req.header('CF-Ray') || crypto.randomUUID();

  if (error instanceof AppError) {
    console.error(JSON.stringify({
      level: 'error',
      requestId,
      code: error.code,
      status: error.statusCode,
      message: error.message,
      details: error.internalDetails,
      path: c.req.url,
      method: c.req.method,
    }));

    return c.json({
      error: error.message,
      code: error.code,
      requestId, // Help users report issues
    }, error.statusCode);
  }

  if (error instanceof z.ZodError) {
    console.error(JSON.stringify({
      level: 'error',
      requestId,
      code: 'VALIDATION_ERROR',
      status: 400,
      errors: error.errors,
      path: c.req.url,
    }));

    return c.json({
      error: 'Validation failed',
      code: 'VALIDATION_ERROR',
      details: error.errors.map(e => `${e.path.join('.')}: ${e.message}`),
      requestId,
    }, 400);
  }

  // Unknown error - log internally but don't expose
  console.error(JSON.stringify({
    level: 'error',
    requestId,
    code: 'INTERNAL_ERROR',
    status: 500,
    error: String(error),
    stack: error instanceof Error ? error.stack : undefined,
    path: c.req.url,
  }));

  return c.json({
    error: 'Internal server error',
    code: 'INTERNAL_ERROR',
    requestId,
  }, 500);
}
```

### 4.2: Structured Logging (10 min)

**File:** `src/utils/logger.ts`

```typescript
export interface LogContext {
  requestId: string;
  path: string;
  method: string;
  userId?: string;
}

export const logger = {
  info(message: string, context: LogContext, data?: Record<string, any>) {
    console.log(JSON.stringify({
      level: 'info',
      message,
      ...context,
      ...data,
      timestamp: Date.now(),
    }));
  },

  warn(message: string, context: LogContext, data?: Record<string, any>) {
    console.warn(JSON.stringify({
      level: 'warn',
      message,
      ...context,
      ...data,
      timestamp: Date.now(),
    }));
  },

  error(message: string, context: LogContext, error?: unknown) {
    console.error(JSON.stringify({
      level: 'error',
      message,
      ...context,
      error: String(error),
      stack: error instanceof Error ? error.stack : undefined,
      timestamp: Date.now(),
    }));
  },
};
```

**Usage in handlers:**

```typescript
export async function registerDevice(c: Context) {
  const context = {
    requestId: c.req.header('CF-Ray') || crypto.randomUUID(),
    path: c.req.url,
    method: c.req.method,
    userId: c.get('user')?.uid,
  };

  try {
    logger.info('Device registration started', context);

    // ... implementation

    logger.info('Device registered successfully', context, {
      deviceId: validatedInput.deviceId,
    });

    return c.json({ success: true });
  } catch (error) {
    return handleError(error, c);
  }
}
```

### 4.3: Golden Test Vector (15 min)

**File:** `test/errors.test.ts`

```typescript
describe('Error Handling', () => {
  it('GOLDEN: user-friendly error messages', () => {
    const error = Errors.NotFound('Device');
    expect(error.message).toBe('Device not found');
    expect(error.statusCode).toBe(404);
    expect(error.code).toBe('NOT_FOUND');
  });

  it('THREAT: does not leak internal details', () => {
    const error = new AppError(
      'User-facing message',
      500,
      'INTERNAL',
      'Internal SQL query failed: SELECT * FROM secrets'
    );

    const mockContext = {
      req: { url: '/test', method: 'POST', header: () => 'test-id' },
      json: vi.fn((body, status) => ({ body, status })),
    } as any;

    const response = handleError(error, mockContext);

    expect(response.body.error).toBe('User-facing message');
    expect(response.body.error).not.toContain('SQL');
    expect(response.body.error).not.toContain('secrets');
  });

  it('THREAT: sanitizes stack traces', () => {
    const error = new Error('Database connection failed');
    error.stack = 'Error: Database connection failed\n  at /home/user/secrets/db.ts:42';

    const mockContext = {
      req: { url: '/test', method: 'POST', header: () => 'test-id' },
      json: vi.fn((body, status) => ({ body, status })),
    } as any;

    const response = handleError(error, mockContext);

    expect(response.body.error).toBe('Internal server error');
    expect(response.body.error).not.toContain('/home/user');
    expect(response.body.error).not.toContain('db.ts');
  });
});
```

**SUCCESS CRITERIA:**
- ✅ User-facing errors are safe
- ✅ Internal details logged but not exposed
- ✅ Structured logs for debugging

---

## Phase 5: Production Readiness (45 min)

**Threat:** API10:2023 Unsafe Consumption of APIs
**Goal:** Cleanup, monitoring, deployment automation

### 5.1: Message Cleanup Cron Job (15 min)

**File:** `src/cron/cleanup.ts`

```typescript
export async function cleanupExpiredMessages(env: any) {
  const db = env.DB;
  const now = Date.now();

  try {
    // Delete expired messages
    const messagesResult = await db.prepare(`
      DELETE FROM encrypted_messages
      WHERE expires_at < ?
    `).bind(now).run();

    // Clean up orphaned delivery records
    const deliveryResult = await db.prepare(`
      DELETE FROM message_delivery
      WHERE message_id NOT IN (
        SELECT message_id FROM encrypted_messages
      )
    `).run();

    console.log(JSON.stringify({
      level: 'info',
      event: 'cleanup_complete',
      messagesDeleted: messagesResult.meta.changes,
      deliveryRecordsDeleted: deliveryResult.meta.changes,
      timestamp: now,
    }));

    return {
      success: true,
      messagesDeleted: messagesResult.meta.changes,
      deliveryRecordsDeleted: deliveryResult.meta.changes,
    };
  } catch (error) {
    console.error(JSON.stringify({
      level: 'error',
      event: 'cleanup_failed',
      error: String(error),
      timestamp: now,
    }));
    throw error;
  }
}
```

**File:** `src/index.ts` (add cron handler)

```typescript
app.get('/cron/cleanup', async (c) => {
  // Verify Cloudflare Cron trigger
  const cronSecret = c.req.header('X-Cloudflare-Cron-Secret');
  if (cronSecret !== c.env.CRON_SECRET) {
    return c.json({ error: 'Unauthorized' }, 401);
  }

  const result = await cleanupExpiredMessages(c.env);
  return c.json(result);
});

// Scheduled trigger
export default {
  async fetch(request, env, ctx) {
    return app.fetch(request, env, ctx);
  },
  async scheduled(event, env, ctx) {
    // Run cleanup daily at 2 AM UTC
    await cleanupExpiredMessages(env);
  },
};
```

**Configure cron in `wrangler.toml`:**

```toml
[triggers]
crons = ["0 2 * * *"]  # Daily at 2 AM UTC

[vars]
CRON_SECRET = "random-secret-here"  # Generate: openssl rand -hex 32
```

### 5.2: Health Check Endpoint (10 min)

**File:** `src/handlers/health.ts`

```typescript
export async function healthCheck(c: Context) {
  const checks = {
    database: false,
    auth: false,
    rateLimit: false,
  };

  try {
    // Test database connection
    await c.env.DB.prepare('SELECT 1').first();
    checks.database = true;

    // Test KV cache
    await c.env.KV_CACHE.get('health-check');
    checks.auth = true;

    // Test rate limiter
    if (c.env.RATE_LIMITER) {
      checks.rateLimit = true;
    }

    const allHealthy = Object.values(checks).every(v => v);

    return c.json({
      status: allHealthy ? 'healthy' : 'degraded',
      checks,
      version: '1.0.0',
      timestamp: Date.now(),
    }, allHealthy ? 200 : 503);
  } catch (error) {
    return c.json({
      status: 'unhealthy',
      checks,
      error: 'Health check failed',
      timestamp: Date.now(),
    }, 503);
  }
}
```

**Add to router:**
```typescript
app.get('/health', healthCheck);
```

### 5.3: Deployment Script (10 min)

**File:** `scripts/deploy.sh`

```bash
#!/bin/bash
set -e

echo "🚀 Deploying Buds Relay to Cloudflare Workers"

# Run tests
echo "Running tests..."
npm test

# Type check
echo "Type checking..."
npx tsc --noEmit

# Deploy to production
echo "Deploying to production..."
wrangler deploy --env production

# Test health endpoint
echo "Testing health endpoint..."
sleep 2
HEALTH_RESPONSE=$(curl -s https://api.getbuds.app/health)
echo "$HEALTH_RESPONSE" | jq .

if echo "$HEALTH_RESPONSE" | jq -e '.status == "healthy"' > /dev/null; then
  echo "✅ Deployment successful!"
else
  echo "❌ Health check failed!"
  exit 1
fi
```

**Make executable:**
```bash
chmod +x scripts/deploy.sh
```

### 5.4: Integration Test (10 min)

**File:** `test/integration.test.ts`

```typescript
describe('End-to-End Integration', () => {
  it('GOLDEN: full E2EE flow', async () => {
    // 1. Register device
    const registerResponse = await fetch('https://api.getbuds.app/api/devices/register', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${TEST_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        deviceId: 'test-device-id',
        deviceName: 'Test Device',
        pubkeyX25519: 'base64-pubkey',
        pubkeyEd25519: 'base64-pubkey',
        ownerDID: 'did:buds:test',
      }),
    });

    expect(registerResponse.status).toBe(200);

    // 2. Lookup DID
    const lookupResponse = await fetch('https://api.getbuds.app/api/lookup/did', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${TEST_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        phoneNumber: '+14155551234',
      }),
    });

    expect(lookupResponse.status).toBe(200);
    const { did } = await lookupResponse.json();
    expect(did).toMatch(/^did:buds:[A-Za-z0-9]+$/);

    // 3. Send message
    const sendResponse = await fetch('https://api.getbuds.app/api/messages/send', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${TEST_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        messageId: 'test-message-id',
        receiptCID: 'bafyreibase58string',
        encryptedPayload: 'base64-encrypted-payload',
        wrappedKeys: { 'test-device-id': 'base64-wrapped-key' },
        recipientDIDs: [did],
        senderDID: 'did:buds:sender',
        senderDeviceId: 'sender-device-id',
      }),
    });

    expect(sendResponse.status).toBe(200);

    // 4. Fetch inbox
    const inboxResponse = await fetch(`https://api.getbuds.app/api/messages/inbox?did=${did}`, {
      headers: {
        'Authorization': `Bearer ${TEST_TOKEN}`,
      },
    });

    expect(inboxResponse.status).toBe(200);
    const { messages } = await inboxResponse.json();
    expect(messages).toHaveLength(1);
    expect(messages[0].message_id).toBe('test-message-id');
  });
});
```

---

## Success Criteria (All Must Pass)

### Phase 1: Authentication
- [ ] `npm test` passes all auth tests (4/4)
- [ ] Invalid tokens rejected with 401
- [ ] Valid Firebase tokens accepted
- [ ] KV cache working (public keys cached)

### Phase 2: Rate Limiting
- [ ] Rate limiting active on all endpoints
- [ ] 429 returned when limit exceeded
- [ ] Different limits per endpoint working
- [ ] Rate limit resets after period

### Phase 3: Input Validation
- [ ] All 15+ validation tests pass
- [ ] SQL injection attempts blocked
- [ ] Malformed DIDs rejected
- [ ] Zod schemas enforce strict types

### Phase 4: Error Handling
- [ ] No internal details leaked in errors
- [ ] Structured JSON logs
- [ ] Request IDs in all responses
- [ ] Error codes documented

### Phase 5: Production Readiness
- [ ] Health check endpoint returns 200
- [ ] Cron job runs successfully (local test)
- [ ] Integration tests pass (full E2EE flow)
- [ ] Deployment script works

---

## Final Hardening Checklist

Before starting Phase 6 implementation:

- [ ] All 5 hardening phases complete
- [ ] All tests passing (`npm test`)
- [ ] Deployed to staging (wrangler deploy --env staging)
- [ ] Manual QA on staging (test with real Firebase token)
- [ ] Load test (k6 or Artillery - 100 concurrent users)
- [ ] Security review (penetration test DID enumeration)
- [ ] Documentation updated (API reference, error codes)

---

## Sources

- [OWASP API Security Top 10 2023](https://owasp.org/API-Security/)
- [Cloudflare Workers Rate Limiting (GA)](https://developers.cloudflare.com/changelog/2025-09-19-ratelimit-workers-ga/)
- [Rate Limiting Best Practices](https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/)
- [firebase-auth-cloudflare-workers on npm](https://www.npmjs.com/package/firebase-auth-cloudflare-workers)
- [GitHub: Code-Hex/firebase-auth-cloudflare-workers](https://github.com/Code-Hex/firebase-auth-cloudflare-workers)
- [Cloudflare Workers Rate Limiting Runtime API](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/)

---

**When this sprint is done:**
- Phase 6 implementation will be **obvious** (tests show the way)
- Security threats **eliminated** (not just mitigated)
- API behavior **proven** (golden vectors + threat vectors)
- Deployment **automated** (scripts + health checks)

**Estimated time:** 4-6 hours (240-360 minutes)
**Complexity reduction:** ~50% less cognitive load during Phase 6 implementation

Let's harden first, implement second. 🔒🚀
