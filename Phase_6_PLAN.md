# Phase 6: E2EE Sharing + Cloudflare Relay

**Last Updated:** December 20, 2025
**Prerequisites:** Phase 5 complete (Circle mechanics working)
**Estimated Time:** 10-14 hours
**Goal:** Enable users to share memories with Circle using E2EE, device registration, and Cloudflare Workers relay

---

## Quick Start for New Agent

**If you're a fresh Claude Code agent:**

1. Read this file completely (45 min)
2. Review `/docs/E2EE_DESIGN.md` for encryption details (30 min)
3. Review Phase 5 completion in `README.md` (10 min)
4. Set up Cloudflare Workers project (30 min)
5. Follow the implementation steps below sequentially
6. Test at each checkpoint before proceeding

**Current State:**
- ✅ Firebase Auth working (phone verification ONLY)
- ✅ Profile view with DID display
- ✅ Memory creation with photos
- ✅ Timeline view
- ✅ Circle mechanics (add/remove/edit members)
- ⏳ E2EE sharing (this phase)
- ⏳ Device registration (this phase)
- ⏳ Cloudflare Workers relay (this phase)

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Cloudflare Setup](#cloudflare-setup)
3. [Workers API Implementation](#workers-api-implementation)
4. [Core Swift Components](#core-swift-components)
5. [E2EE Implementation](#e2ee-implementation)
6. [UI Updates](#ui-updates)
7. [Testing Checkpoints](#testing-checkpoints)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### What Changes in Phase 6?

**Phase 5 (Local-Only):**
- Circle members have placeholder DIDs (`did:buds:placeholder_xxx`)
- No real sharing - just UI mockup
- No relay server

**Phase 6 (E2EE Sharing):**
- Device registration on first launch (send device pubkeys to Cloudflare Workers)
- Phone → DID lookup via Workers API
- Share memories → Encrypt with recipient device pubkeys
- Cloudflare Workers as untrusted relay (sees only ciphertext)
- Recipients poll for messages and decrypt locally

### E2EE Flow (Simplified)

```
1. Alice shares memory with Bob
   ↓
2. Look up Bob's devices from Cloudflare D1
   ↓
3. Generate ephemeral AES-256 key
   ↓
4. Encrypt memory (raw CBOR) with AES-256-GCM
   ↓
5. Wrap AES key for each of Bob's devices (X25519 key agreement)
   ↓
6. POST encrypted message to Cloudflare Workers
   ↓
7. Workers store in D1, return success
   ↓
8. Bob's device polls /messages/inbox, downloads message
   ↓
9. Bob unwraps AES key, decrypts, verifies signature
   ↓
10. Store decrypted receipt in local DB
```

### Key Architectural Decisions

1. **Cloudflare Workers as Relay**: Zero-trust relay server (edge compute, sees only ciphertext)
2. **Cloudflare D1 Storage**: SQLite at the edge for device registry and message queue
3. **Firebase Auth Only**: Phone verification ONLY - no Firestore, no Cloud Functions
4. **Device-Based Encryption**: Each device gets unique X25519 keypair (multi-device support)
5. **Ephemeral AES Keys**: Each message uses new AES-256 key (wrapped per device)
6. **Raw CBOR Encryption**: Encrypt canonical CBOR bytes (not JSON) to preserve signature verification
7. **HTTP Polling**: Phase 6 uses polling (Phase 7+ will add push notifications)

### Infrastructure Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Auth | Firebase Auth | Phone verification only |
| Relay API | Cloudflare Workers | E2EE message routing |
| Storage | Cloudflare D1 (SQLite) | Device registry, message queue |
| Client | Swift + CryptoKit | Encryption, local storage |

---

## Cloudflare Setup

### Step 1: Create Cloudflare Workers Project

```bash
# Create new project directory
mkdir buds-relay
cd buds-relay

# Initialize Workers project
npm create cloudflare@latest

# Project name: buds-relay
# Type: "Hello World" Worker
# TypeScript: Yes
# Git: Yes
# Deploy: No (we'll test locally first)
```

### Step 2: Install D1 CLI

```bash
# Already installed with Wrangler (Cloudflare CLI)
npx wrangler --version
```

### Step 3: Create D1 Database

```bash
# Create production database
npx wrangler d1 create buds-relay-db

# Output will show:
# Database created: buds-relay-db
# UUID: xxxx-xxxx-xxxx-xxxx

# Add to wrangler.toml:
# [[d1_databases]]
# binding = "DB"
# database_name = "buds-relay-db"
# database_id = "xxxx-xxxx-xxxx-xxxx"
```

### Step 4: Initialize D1 Schema

Create `schema.sql`:

```sql
-- Devices table
CREATE TABLE devices (
    device_id TEXT PRIMARY KEY NOT NULL,
    owner_did TEXT NOT NULL,
    owner_phone_hash TEXT NOT NULL,
    device_name TEXT NOT NULL,
    pubkey_x25519 TEXT NOT NULL,
    pubkey_ed25519 TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    registered_at INTEGER NOT NULL,
    last_seen_at INTEGER
);

CREATE INDEX idx_devices_owner_did ON devices(owner_did);
CREATE INDEX idx_devices_phone_hash ON devices(owner_phone_hash);
CREATE INDEX idx_devices_status ON devices(status);

-- Encrypted messages table
CREATE TABLE encrypted_messages (
    message_id TEXT PRIMARY KEY NOT NULL,
    receipt_cid TEXT NOT NULL,
    sender_did TEXT NOT NULL,
    sender_device_id TEXT NOT NULL,
    recipient_dids TEXT NOT NULL,
    encrypted_payload TEXT NOT NULL,
    wrapped_keys TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE INDEX idx_messages_recipient ON encrypted_messages(recipient_dids);
CREATE INDEX idx_messages_expires ON encrypted_messages(expires_at);

-- Phone to DID mapping
CREATE TABLE phone_to_did (
    phone_hash TEXT PRIMARY KEY NOT NULL,
    did TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

-- Message delivery tracking (for inbox polling)
CREATE TABLE message_delivery (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id TEXT NOT NULL,
    recipient_did TEXT NOT NULL,
    delivered_at INTEGER,
    FOREIGN KEY (message_id) REFERENCES encrypted_messages(message_id)
);

CREATE INDEX idx_delivery_recipient ON message_delivery(recipient_did);
CREATE INDEX idx_delivery_status ON message_delivery(delivered_at);
```

Apply schema:

```bash
# Local development
npx wrangler d1 execute buds-relay-db --local --file=schema.sql

# Production
npx wrangler d1 execute buds-relay-db --remote --file=schema.sql
```

### Step 5: Configure wrangler.toml

```toml
name = "buds-relay"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[env.production]
name = "buds-relay"
routes = [
  { pattern = "api.getbuds.app/*", zone_name = "getbuds.app" }
]

[[d1_databases]]
binding = "DB"
database_name = "buds-relay-db"
database_id = "YOUR_DATABASE_ID_HERE"

[vars]
ENVIRONMENT = "production"
```

---

## Workers API Implementation

### Project Structure

```
buds-relay/
├── src/
│   ├── index.ts           # Main router
│   ├── handlers/
│   │   ├── devices.ts     # Device registration
│   │   ├── lookup.ts      # DID lookup
│   │   ├── messages.ts    # Message send/receive
│   └── utils/
│       ├── auth.ts        # Firebase Auth verification
│       ├── crypto.ts      # Hashing utilities
│       └── db.ts          # Database helpers
├── schema.sql
├── package.json
├── tsconfig.json
└── wrangler.toml
```

### src/index.ts

Main router for all API endpoints.

```typescript
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { registerDevice, getDevices } from './handlers/devices';
import { lookupDID } from './handlers/lookup';
import { sendMessage, getInbox } from './handlers/messages';

type Bindings = {
  DB: D1Database;
};

const app = new Hono<{ Bindings: Bindings }>();

// CORS configuration
app.use('/*', cors({
  origin: '*', // TODO: Restrict to app domains in production
  allowMethods: ['GET', 'POST', 'OPTIONS'],
  allowHeaders: ['Content-Type', 'Authorization'],
}));

// Health check
app.get('/health', (c) => c.json({ status: 'ok' }));

// Device endpoints
app.post('/api/devices/register', registerDevice);
app.post('/api/devices/list', getDevices);

// Lookup endpoints
app.post('/api/lookup/did', lookupDID);

// Message endpoints
app.post('/api/messages/send', sendMessage);
app.get('/api/messages/inbox', getInbox);

export default app;
```

### src/handlers/devices.ts

Device registration and discovery.

```typescript
import { Context } from 'hono';
import { verifyFirebaseToken } from '../utils/auth';
import { hashPhone } from '../utils/crypto';

export async function registerDevice(c: Context) {
  try {
    // Verify Firebase Auth token
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const token = authHeader.substring(7);
    const user = await verifyFirebaseToken(token);

    // Parse request body
    const body = await c.req.json();
    const { deviceId, deviceName, pubkeyX25519, pubkeyEd25519, ownerDID } = body;

    if (!deviceId || !deviceName || !pubkeyX25519 || !pubkeyEd25519 || !ownerDID) {
      return c.json({ error: 'Missing required fields' }, 400);
    }

    // Hash phone number for privacy
    const phoneHash = hashPhone(user.phoneNumber);

    // Store device in D1
    const db = c.env.DB;
    const now = Date.now();

    await db.prepare(`
      INSERT INTO devices (device_id, owner_did, owner_phone_hash, device_name,
                          pubkey_x25519, pubkey_ed25519, status, registered_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, ?, 'active', ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        last_seen_at = ?,
        status = 'active'
    `).bind(
      deviceId,
      ownerDID,
      phoneHash,
      deviceName,
      pubkeyX25519,
      pubkeyEd25519,
      now,
      now,
      now
    ).run();

    // Map phone → DID
    await db.prepare(`
      INSERT INTO phone_to_did (phone_hash, did, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(phone_hash) DO UPDATE SET
        did = ?,
        updated_at = ?
    `).bind(phoneHash, ownerDID, now, ownerDID, now).run();

    return c.json({ success: true, deviceId });
  } catch (error) {
    console.error('Device registration error:', error);
    return c.json({ error: 'Internal server error' }, 500);
  }
}

export async function getDevices(c: Context) {
  try {
    // Verify Firebase Auth token
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const token = authHeader.substring(7);
    await verifyFirebaseToken(token);

    // Parse request
    const body = await c.req.json();
    const { dids } = body;

    if (!Array.isArray(dids) || dids.length === 0) {
      return c.json({ error: 'Invalid DIDs array' }, 400);
    }

    // Query devices (max 12 DIDs for Circle limit)
    const db = c.env.DB;
    const placeholders = dids.map(() => '?').join(',');
    const query = `
      SELECT device_id, owner_did, device_name, pubkey_x25519, pubkey_ed25519, status
      FROM devices
      WHERE owner_did IN (${placeholders}) AND status = 'active'
    `;

    const result = await db.prepare(query).bind(...dids).all();

    return c.json({ devices: result.results });
  } catch (error) {
    console.error('Get devices error:', error);
    return c.json({ error: 'Internal server error' }, 500);
  }
}
```

### src/handlers/lookup.ts

Phone number to DID lookup.

```typescript
import { Context } from 'hono';
import { verifyFirebaseToken } from '../utils/auth';
import { hashPhone } from '../utils/crypto';

export async function lookupDID(c: Context) {
  try {
    // Verify Firebase Auth token
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const token = authHeader.substring(7);
    await verifyFirebaseToken(token);

    // Parse request
    const body = await c.req.json();
    const { phoneNumber } = body;

    if (!phoneNumber) {
      return c.json({ error: 'Phone number required' }, 400);
    }

    // Hash phone for lookup
    const phoneHash = hashPhone(phoneNumber);

    // Query D1
    const db = c.env.DB;
    const result = await db.prepare(`
      SELECT did FROM phone_to_did WHERE phone_hash = ?
    `).bind(phoneHash).first();

    if (!result) {
      return c.json({ error: 'User not found' }, 404);
    }

    return c.json({ did: result.did });
  } catch (error) {
    console.error('DID lookup error:', error);
    return c.json({ error: 'Internal server error' }, 500);
  }
}
```

### src/handlers/messages.ts

Message send and inbox retrieval.

```typescript
import { Context } from 'hono';
import { verifyFirebaseToken } from '../utils/auth';

export async function sendMessage(c: Context) {
  try {
    // Verify Firebase Auth token
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const token = authHeader.substring(7);
    await verifyFirebaseToken(token);

    // Parse request
    const body = await c.req.json();
    const {
      messageId,
      receiptCID,
      encryptedPayload,
      wrappedKeys,
      recipientDIDs,
      senderDID,
      senderDeviceId
    } = body;

    if (!messageId || !receiptCID || !encryptedPayload || !wrappedKeys || !recipientDIDs || !senderDID || !senderDeviceId) {
      return c.json({ error: 'Missing required fields' }, 400);
    }

    const db = c.env.DB;
    const now = Date.now();
    const expiresAt = now + (30 * 24 * 60 * 60 * 1000); // 30 days

    // Store encrypted message
    await db.prepare(`
      INSERT INTO encrypted_messages
      (message_id, receipt_cid, sender_did, sender_device_id, recipient_dids,
       encrypted_payload, wrapped_keys, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).bind(
      messageId,
      receiptCID,
      senderDID,
      senderDeviceId,
      JSON.stringify(recipientDIDs),
      encryptedPayload,
      JSON.stringify(wrappedKeys),
      now,
      expiresAt
    ).run();

    // Create delivery records for each recipient
    for (const recipientDID of recipientDIDs) {
      await db.prepare(`
        INSERT INTO message_delivery (message_id, recipient_did, delivered_at)
        VALUES (?, ?, NULL)
      `).bind(messageId, recipientDID).run();
    }

    return c.json({ success: true, messageId });
  } catch (error) {
    console.error('Send message error:', error);
    return c.json({ error: 'Internal server error' }, 500);
  }
}

export async function getInbox(c: Context) {
  try {
    // Verify Firebase Auth token
    const authHeader = c.req.header('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return c.json({ error: 'Unauthorized' }, 401);
    }

    const token = authHeader.substring(7);
    const user = await verifyFirebaseToken(token);

    // Get DID from query params
    const did = c.req.query('did');
    if (!did) {
      return c.json({ error: 'DID required' }, 400);
    }

    const db = c.env.DB;

    // Get undelivered messages for this DID
    const result = await db.prepare(`
      SELECT m.message_id, m.receipt_cid, m.sender_did, m.sender_device_id,
             m.encrypted_payload, m.wrapped_keys, m.created_at
      FROM encrypted_messages m
      INNER JOIN message_delivery d ON m.message_id = d.message_id
      WHERE d.recipient_did = ? AND d.delivered_at IS NULL
      ORDER BY m.created_at DESC
      LIMIT 50
    `).bind(did).all();

    // Mark as delivered
    const messageIds = result.results.map((m: any) => m.message_id);
    if (messageIds.length > 0) {
      const placeholders = messageIds.map(() => '?').join(',');
      const now = Date.now();
      await db.prepare(`
        UPDATE message_delivery
        SET delivered_at = ?
        WHERE recipient_did = ? AND message_id IN (${placeholders}) AND delivered_at IS NULL
      `).bind(now, did, ...messageIds).run();
    }

    // Parse JSON fields
    const messages = result.results.map((m: any) => ({
      ...m,
      wrapped_keys: JSON.parse(m.wrapped_keys)
    }));

    return c.json({ messages });
  } catch (error) {
    console.error('Get inbox error:', error);
    return c.json({ error: 'Internal server error' }, 500);
  }
}
```

### src/utils/auth.ts

Firebase Auth token verification.

```typescript
export async function verifyFirebaseToken(token: string): Promise<{ uid: string; phoneNumber: string }> {
  // Use Firebase Admin SDK or REST API to verify token
  // For simplicity, using Firebase REST API

  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: token })
    }
  );

  if (!response.ok) {
    throw new Error('Invalid token');
  }

  const data = await response.json();
  const user = data.users?.[0];

  if (!user) {
    throw new Error('User not found');
  }

  return {
    uid: user.localId,
    phoneNumber: user.phoneNumber
  };
}

// TODO: Set this in wrangler.toml secrets
const FIREBASE_API_KEY = 'your-firebase-api-key';
```

### src/utils/crypto.ts

Hashing utilities.

```typescript
export function hashPhone(phoneNumber: string): string {
  // Normalize phone number (remove spaces, dashes)
  const normalized = phoneNumber.replace(/[\s\-\(\)]/g, '');

  // SHA-256 hash
  const encoder = new TextEncoder();
  const data = encoder.encode(normalized);

  return crypto.subtle.digest('SHA-256', data).then(hash => {
    return Array.from(new Uint8Array(hash))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
  });
}
```

### package.json

```json
{
  "name": "buds-relay",
  "version": "1.0.0",
  "scripts": {
    "dev": "wrangler dev",
    "deploy": "wrangler deploy"
  },
  "dependencies": {
    "hono": "^3.11.0"
  },
  "devDependencies": {
    "@cloudflare/workers-types": "^4.20231218.0",
    "wrangler": "^3.22.0",
    "typescript": "^5.3.3"
  }
}
```

### Deploy Workers

```bash
# Test locally
npm run dev

# Deploy to production
npm run deploy
```

---

## Core Swift Components

### 1. RelayClient

**Location:** `Buds/Buds/Buds/Core/RelayClient.swift` (create new file)

HTTP client for Cloudflare Workers API.

```swift
//
//  RelayClient.swift
//  Buds
//
//  Cloudflare Workers relay client
//

import Foundation
import FirebaseAuth

class RelayClient {
    static let shared = RelayClient()

    private let baseURL = "https://api.getbuds.app"  // TODO: Update with your Workers domain

    private init() {}

    // MARK: - Auth Header

    private func getAuthHeader() async throws -> [String: String] {
        guard let user = Auth.auth().currentUser else {
            throw RelayError.notAuthenticated
        }

        let token = try await user.getIDToken()
        return ["Authorization": "Bearer \(token)"]
    }

    // MARK: - Device Registration

    func registerDevice(
        deviceId: String,
        deviceName: String,
        pubkeyX25519: String,
        pubkeyEd25519: String,
        ownerDID: String
    ) async throws {
        let headers = try await getAuthHeader()
        let url = URL(string: "\(baseURL)/api/devices/register")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = [
            "deviceId": deviceId,
            "deviceName": deviceName,
            "pubkeyX25519": pubkeyX25519,
            "pubkeyEd25519": pubkeyEd25519,
            "ownerDID": ownerDID
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RelayError.serverError
        }
    }

    // MARK: - DID Lookup

    func lookupDID(phoneNumber: String) async throws -> String {
        let headers = try await getAuthHeader()
        let url = URL(string: "\(baseURL)/api/lookup/did")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = ["phoneNumber": phoneNumber]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 404 {
                throw RelayError.userNotFound
            }
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let did = json?["did"] as? String else {
            throw RelayError.invalidResponse
        }

        return did
    }

    // MARK: - Get Devices

    func getDevices(for dids: [String]) async throws -> [[String: Any]] {
        let headers = try await getAuthHeader()
        let url = URL(string: "\(baseURL)/api/devices/list")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let body: [String: Any] = ["dids": dids]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let devices = json?["devices"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        return devices
    }

    // MARK: - Send Message

    func sendMessage(_ message: EncryptedMessage) async throws {
        let headers = try await getAuthHeader()
        let url = URL(string: "\(baseURL)/api/messages/send")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(message)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RelayError.serverError
        }
    }

    // MARK: - Get Inbox

    func getInbox(for did: String) async throws -> [EncryptedMessage] {
        let headers = try await getAuthHeader()
        let url = URL(string: "\(baseURL)/api/messages/inbox?did=\(did)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RelayError.serverError
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let messagesArray = json?["messages"] as? [[String: Any]] else {
            throw RelayError.invalidResponse
        }

        return try messagesArray.map { dict in
            try parseEncryptedMessage(dict)
        }
    }

    // MARK: - Helper

    private func parseEncryptedMessage(_ dict: [String: Any]) throws -> EncryptedMessage {
        guard
            let messageId = dict["message_id"] as? String,
            let receiptCID = dict["receipt_cid"] as? String,
            let encryptedPayload = dict["encrypted_payload"] as? String,
            let wrappedKeys = dict["wrapped_keys"] as? [String: String],
            let senderDID = dict["sender_did"] as? String,
            let senderDeviceId = dict["sender_device_id"] as? String,
            let createdAtMs = dict["created_at"] as? Int64
        else {
            throw RelayError.invalidResponse
        }

        return EncryptedMessage(
            messageId: messageId,
            receiptCID: receiptCID,
            encryptedPayload: encryptedPayload,
            wrappedKeys: wrappedKeys,
            senderDID: senderDID,
            senderDeviceId: senderDeviceId,
            createdAt: Date(timeIntervalSince1970: Double(createdAtMs) / 1000)
        )
    }
}

// MARK: - Errors

enum RelayError: Error, LocalizedError {
    case notAuthenticated
    case serverError
    case userNotFound
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .serverError:
            return "Server error"
        case .userNotFound:
            return "User not found"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}
```

### 2. DeviceManager

**Location:** `Buds/Buds/Buds/Core/DeviceManager.swift` (create new file)

Manages current device registration and device discovery.

```swift
//
//  DeviceManager.swift
//  Buds
//
//  Manages device registration and discovery
//

import Foundation

@MainActor
class DeviceManager: ObservableObject {
    static let shared = DeviceManager()

    @Published var currentDevice: Device?
    @Published var isRegistered = false

    private init() {
        Task {
            await loadCurrentDevice()
        }
    }

    // MARK: - Device Registration

    func registerDevice() async throws {
        let identityManager = IdentityManager.shared
        let deviceId = try identityManager.deviceId
        let ownerDID = try identityManager.currentDID

        // Get keypairs
        let x25519Keys = try identityManager.getX25519Keypair()
        let ed25519Keys = try identityManager.getEd25519Keypair()

        let deviceName = await UIDevice.current.name

        // Call Cloudflare Workers
        try await RelayClient.shared.registerDevice(
            deviceId: deviceId,
            deviceName: deviceName,
            pubkeyX25519: x25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            pubkeyEd25519: ed25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            ownerDID: ownerDID
        )

        print("✅ Device registered: \(deviceId)")

        // Store locally
        let device = Device(
            deviceId: deviceId,
            ownerDID: ownerDID,
            deviceName: deviceName,
            pubkeyX25519: x25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            pubkeyEd25519: ed25519Keys.publicKey.rawRepresentation.base64EncodedString(),
            status: .active,
            registeredAt: Date(),
            lastSeenAt: Date()
        )

        let db = Database.shared
        try await db.writeAsync { db in
            try device.insert(db)
        }

        currentDevice = device
        isRegistered = true
    }

    // MARK: - Load Current Device

    func loadCurrentDevice() async {
        do {
            let deviceId = try IdentityManager.shared.deviceId
            let db = Database.shared

            let device = try await db.readAsync { db in
                try Device
                    .filter(Device.Columns.deviceId == deviceId)
                    .fetchOne(db)
            }

            currentDevice = device
            isRegistered = device != nil
        } catch {
            print("❌ Failed to load current device: \(error)")
        }
    }

    // MARK: - Get Devices for DIDs

    func getDevices(for dids: [String]) async throws -> [Device] {
        let devicesData = try await RelayClient.shared.getDevices(for: dids)

        return try devicesData.map { dict in
            try parseDevice(dict)
        }
    }

    // MARK: - Helper

    private func parseDevice(_ dict: [String: Any]) throws -> Device {
        guard
            let deviceId = dict["device_id"] as? String,
            let ownerDID = dict["owner_did"] as? String,
            let deviceName = dict["device_name"] as? String,
            let pubkeyX25519 = dict["pubkey_x25519"] as? String,
            let pubkeyEd25519 = dict["pubkey_ed25519"] as? String,
            let statusStr = dict["status"] as? String,
            let status = Device.DeviceStatus(rawValue: statusStr)
        else {
            throw DeviceError.invalidResponse
        }

        return Device(
            deviceId: deviceId,
            ownerDID: ownerDID,
            deviceName: deviceName,
            pubkeyX25519: pubkeyX25519,
            pubkeyEd25519: pubkeyEd25519,
            status: status,
            registeredAt: Date(),
            lastSeenAt: nil
        )
    }
}

// MARK: - Errors

enum DeviceError: Error, LocalizedError {
    case invalidResponse
    case notRegistered

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .notRegistered:
            return "Device not registered"
        }
    }
}
```

### 3. E2EEManager

**Location:** `Buds/Buds/Buds/Core/E2EEManager.swift` (create new file)

Handles encryption/decryption of messages.

```swift
//
//  E2EEManager.swift
//  Buds
//
//  End-to-end encryption manager
//

import Foundation
import CryptoKit

@MainActor
class E2EEManager {
    static let shared = E2EEManager()

    private init() {}

    // MARK: - Encrypt Message

    func encryptMessage(
        receiptCID: String,
        rawCBOR: Data,
        recipientDevices: [Device]
    ) throws -> EncryptedMessage {
        // 1. Generate ephemeral AES key
        let aesKey = SymmetricKey(size: .bits256)

        // 2. Encrypt payload with AES-GCM
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            rawCBOR,
            using: aesKey,
            nonce: nonce,
            authenticating: receiptCID.data(using: .utf8)!  // AAD = receipt CID
        )

        // 3. Get sender keys
        let identityManager = IdentityManager.shared
        let senderPrivateKey = try identityManager.getX25519Keypair().privateKey
        let senderDID = try identityManager.currentDID
        let senderDeviceId = try identityManager.deviceId

        // 4. Wrap AES key for each recipient device
        var wrappedKeys: [String: String] = [:]  // deviceId -> base64 wrapped key

        for device in recipientDevices {
            let wrapped = try wrapKey(
                aesKey,
                forRecipient: device.pubkeyX25519,
                senderPrivateKey: senderPrivateKey
            )
            wrappedKeys[device.deviceId] = wrapped.base64EncodedString()
        }

        // 5. Create encrypted message
        return EncryptedMessage(
            messageId: UUID().uuidString,
            receiptCID: receiptCID,
            encryptedPayload: sealed.combined.base64EncodedString(),
            wrappedKeys: wrappedKeys,
            senderDID: senderDID,
            senderDeviceId: senderDeviceId,
            createdAt: Date()
        )
    }

    // MARK: - Decrypt Message

    func decryptMessage(_ encryptedMessage: EncryptedMessage) throws -> Data {
        let identityManager = IdentityManager.shared
        let myDeviceId = try identityManager.deviceId
        let myPrivateKey = try identityManager.getX25519Keypair().privateKey

        // 1. Find wrapped key for my device
        guard let wrappedKeyB64 = encryptedMessage.wrappedKeys[myDeviceId] else {
            throw E2EEError.noKeyForDevice
        }

        guard let wrappedKeyData = Data(base64Encoded: wrappedKeyB64) else {
            throw E2EEError.invalidWrappedKey
        }

        // 2. Unwrap AES key
        let aesKey = try unwrapKey(
            wrappedKeyData,
            fromSender: encryptedMessage.senderDeviceId,
            myPrivateKey: myPrivateKey
        )

        // 3. Decrypt payload
        guard let encryptedData = Data(base64Encoded: encryptedMessage.encryptedPayload) else {
            throw E2EEError.invalidPayload
        }

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)

        let rawCBOR = try AES.GCM.open(
            sealedBox,
            using: aesKey,
            authenticating: encryptedMessage.receiptCID.data(using: .utf8)!  // AAD = receipt CID
        )

        return rawCBOR
    }

    // MARK: - Key Wrapping

    private func wrapKey(
        _ aesKey: SymmetricKey,
        forRecipient recipientPubkeyB64: String,
        senderPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        // 1. Parse recipient public key
        guard let recipientKeyData = Data(base64Encoded: recipientPubkeyB64) else {
            throw E2EEError.invalidPublicKey
        }

        let recipientKey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: recipientKeyData
        )

        // 2. Perform X25519 key agreement
        let sharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(
            with: recipientKey
        )

        // 3. Derive wrapping key with HKDF
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        // 4. Wrap AES key with AES-GCM
        let wrapNonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(
            aesKey.withUnsafeBytes { Data($0) },
            using: wrappingKey,
            nonce: wrapNonce
        )

        // 5. Return: nonce || ciphertext || tag
        var result = Data()
        result.append(wrapNonce.withUnsafeBytes { Data($0) })
        result.append(sealed.ciphertext)
        result.append(sealed.tag)

        return result
    }

    // MARK: - Key Unwrapping

    private func unwrapKey(
        _ wrappedData: Data,
        fromSender senderDeviceId: String,
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> SymmetricKey {
        // 1. Get sender's public key from local DB
        let senderDevice = try await getDeviceFromDB(deviceId: senderDeviceId)

        guard let senderPubkeyData = Data(base64Encoded: senderDevice.pubkeyX25519) else {
            throw E2EEError.invalidPublicKey
        }

        let senderPubkey = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: senderPubkeyData
        )

        // 2. Perform X25519 key agreement (same shared secret)
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(
            with: senderPubkey
        )

        // 3. Derive wrapping key with HKDF
        let wrappingKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "buds.wrap.v1".data(using: .utf8)!,
            outputByteCount: 32
        )

        // 4. Parse wrapped data: nonce (12) || ciphertext || tag (16)
        guard wrappedData.count >= 28 else {  // 12 + 16 minimum
            throw E2EEError.invalidWrappedKey
        }

        let nonce = try AES.GCM.Nonce(data: wrappedData.prefix(12))
        let ciphertext = wrappedData.dropFirst(12).dropLast(16)
        let tag = wrappedData.suffix(16)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        // 5. Unwrap AES key
        let unwrappedData = try AES.GCM.open(sealedBox, using: wrappingKey)

        return SymmetricKey(data: unwrappedData)
    }

    // MARK: - Helper

    private func getDeviceFromDB(deviceId: String) async throws -> Device {
        let db = Database.shared
        let device = try await db.readAsync { db in
            try Device
                .filter(Device.Columns.deviceId == deviceId)
                .fetchOne(db)
        }

        guard let device = device else {
            throw E2EEError.deviceNotFound
        }

        return device
    }
}

// MARK: - Errors

enum E2EEError: Error, LocalizedError {
    case noKeyForDevice
    case invalidWrappedKey
    case invalidPayload
    case invalidPublicKey
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .noKeyForDevice:
            return "No encryption key found for this device"
        case .invalidWrappedKey:
            return "Invalid wrapped key format"
        case .invalidPayload:
            return "Invalid encrypted payload"
        case .invalidPublicKey:
            return "Invalid public key"
        case .deviceNotFound:
            return "Device not found in local database"
        }
    }
}
```

### 4. EncryptedMessage Model

**Location:** `Buds/Buds/Buds/Core/Models/EncryptedMessage.swift` (create new file)

```swift
//
//  EncryptedMessage.swift
//  Buds
//
//  Represents an encrypted message ready for relay
//

import Foundation

struct EncryptedMessage: Codable {
    let messageId: String
    let receiptCID: String
    let encryptedPayload: String  // Base64 encoded: nonce || ciphertext || tag
    let wrappedKeys: [String: String]  // deviceId -> base64 wrapped AES key
    let senderDID: String
    let senderDeviceId: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case receiptCID = "receipt_cid"
        case encryptedPayload = "encrypted_payload"
        case wrappedKeys = "wrapped_keys"
        case senderDID = "sender_did"
        case senderDeviceId = "sender_device_id"
        case createdAt = "created_at"
    }
}
```

### 5. ShareManager

**Location:** `Buds/Buds/Buds/Core/ShareManager.swift` (create new file)

Orchestrates the sharing flow (combines E2EE + Cloudflare Workers).

```swift
//
//  ShareManager.swift
//  Buds
//
//  Manages sharing memories with Circle
//

import Foundation
import Combine

@MainActor
class ShareManager: ObservableObject {
    static let shared = ShareManager()

    @Published var isSharing = false

    private init() {}

    // MARK: - Share Memory

    func shareMemory(memoryCID: String, with circleDIDs: [String]) async throws {
        isSharing = true
        defer { isSharing = false }

        // 1. Load receipt's raw CBOR bytes from DB
        let db = Database.shared
        let rawCBOR = try await db.readAsync { db in
            try UCRHeader
                .filter(UCRHeader.Columns.cid == memoryCID)
                .fetchOne(db)?.rawCBOR
        }

        guard let rawCBOR = rawCBOR else {
            throw ShareError.receiptNotFound
        }

        // 2. Get recipient devices
        let recipientDevices = try await DeviceManager.shared.getDevices(for: circleDIDs)

        guard !recipientDevices.isEmpty else {
            throw ShareError.noDevicesFound
        }

        // 3. Encrypt message
        let encryptedMessage = try E2EEManager.shared.encryptMessage(
            receiptCID: memoryCID,
            rawCBOR: rawCBOR,
            recipientDevices: recipientDevices
        )

        // 4. Send to Cloudflare Workers
        try await RelayClient.shared.sendMessage(encryptedMessage)

        print("✅ Memory shared: \(memoryCID)")

        // 5. Mark memory as shared locally
        try await markMemoryAsShared(memoryCID, recipientDIDs: circleDIDs)
    }

    // MARK: - Mark as Shared

    private func markMemoryAsShared(_ memoryCID: String, recipientDIDs: [String]) async throws {
        // Update local_receipts or create shared_memories entry
        // For now, just log
        print("TODO: Mark memory as shared in local DB")
    }
}

// MARK: - Errors

enum ShareError: Error, LocalizedError {
    case receiptNotFound
    case noDevicesFound

    var errorDescription: String? {
        switch self {
        case .receiptNotFound:
            return "Memory not found"
        case .noDevicesFound:
            return "No devices found for recipients"
        }
    }
}
```

---

## E2EE Implementation

### Step 1: Update IdentityManager

Add device ID generation and X25519 keypair retrieval.

**Location:** `Buds/Buds/Buds/Core/ChaingeKernel/IdentityManager.swift`

Add these methods:

```swift
// MARK: - Device ID

var deviceId: String {
    get throws {
        // Check keychain first
        if let existingId = try? keychain.getString("device_id") {
            return existingId
        }

        // Generate new device ID
        let newId = UUID().uuidString
        try keychain.set(newId, key: "device_id")
        return newId
    }
}

// MARK: - X25519 Keypair (for encryption)

func getX25519Keypair() throws -> (publicKey: Curve25519.KeyAgreement.PublicKey, privateKey: Curve25519.KeyAgreement.PrivateKey) {
    // Check keychain
    if let privateKeyData = try? keychain.getData("x25519_private_key"),
       let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData) {
        return (privateKey.publicKey, privateKey)
    }

    // Generate new keypair
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    try keychain.set(privateKey.rawRepresentation, key: "x25519_private_key")

    print("✅ Generated X25519 keypair")
    return (privateKey.publicKey, privateKey)
}
```

### Step 2: Device Registration on First Launch

Update `BudsApp.swift` to register device after auth.

**Location:** `Buds/Buds/Buds/BudsApp.swift`

```swift
.task {
    // Register device if signed in and not yet registered
    if AuthManager.shared.isSignedIn && !DeviceManager.shared.isRegistered {
        do {
            try await DeviceManager.shared.registerDevice()
        } catch {
            print("❌ Device registration failed: \(error)")
        }
    }
}
```

### Step 3: Update CircleManager to Use Real DIDs

Replace placeholder DID generation with Cloudflare Workers lookup.

**Location:** `Buds/Buds/Buds/Core/CircleManager.swift`

```swift
func addMember(phoneNumber: String, displayName: String) async throws {
    guard members.count < maxCircleSize else {
        throw CircleError.circleFull
    }

    // Look up DID via Cloudflare Workers
    let did = try await RelayClient.shared.lookupDID(phoneNumber: phoneNumber)

    // Get their devices
    let devices = try await DeviceManager.shared.getDevices(for: [did])
    guard let firstDevice = devices.first else {
        throw CircleError.userNotRegistered
    }

    let member = CircleMember(
        id: UUID().uuidString,
        did: did,
        displayName: displayName,
        phoneNumber: phoneNumber,
        avatarCID: nil,
        pubkeyX25519: firstDevice.pubkeyX25519,  // Use real pubkey
        status: .active,  // Active immediately if found
        joinedAt: Date(),
        invitedAt: Date(),
        removedAt: nil,
        createdAt: Date(),
        updatedAt: Date()
    )

    let db = Database.shared
    try await db.writeAsync { db in
        try member.insert(db)
    }

    await loadMembers()
    print("✅ Added Circle member: \(displayName)")
}
```

Add new error cases:

```swift
enum CircleError: Error, LocalizedError {
    case circleFull
    case memberNotFound
    case invalidPhoneNumber
    case userNotFound
    case userNotRegistered

    var errorDescription: String? {
        switch self {
        case .circleFull:
            return "Your Circle is full (max 12 members)"
        case .memberNotFound:
            return "Circle member not found"
        case .invalidPhoneNumber:
            return "Invalid phone number"
        case .userNotFound:
            return "User not found. They may not have signed up yet."
        case .userNotRegistered:
            return "User hasn't registered any devices yet"
        }
    }
}
```

---

## UI Updates

### 1. Add "Share to Circle" Button to MemoryDetailView

**Location:** `Buds/Buds/Buds/Features/Timeline/MemoryDetailView.swift`

Add state and share button in toolbar:

```swift
@State private var showingShareSheet = false

// ... in body:

.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
            Button(action: { showingShareSheet = true }) {
                Label("Share to Circle", systemImage: "person.2.fill")
            }

            Button(action: { /* TODO: Share externally */ }) {
                Label("Share Externally", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .foregroundColor(.budsPrimary)
        }
    }
}
.sheet(isPresented: $showingShareSheet) {
    ShareToCircleView(memoryCID: memory.receiptCID)
}
```

### 2. Create ShareToCircleView

**Location:** `Buds/Buds/Buds/Features/Share/ShareToCircleView.swift` (create new file)

```swift
//
//  ShareToCircleView.swift
//  Buds
//
//  Share memory to Circle members
//

import SwiftUI

struct ShareToCircleView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var circleManager = CircleManager.shared
    @StateObject private var shareManager = ShareManager.shared

    let memoryCID: String

    @State private var selectedMemberDIDs: Set<String> = []
    @State private var shareError: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.budsPrimary)

                    Text("Share to Circle")
                        .font(.budsTitle)
                        .foregroundColor(.white)

                    Text("Select who can see this memory. Messages are end-to-end encrypted.")
                        .font(.budsBody)
                        .foregroundColor(.budsTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .padding(.top, 40)
                .padding(.bottom, 24)

                // Member selection list
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(circleManager.members, id: \.id) { member in
                            MemberSelectionRow(
                                member: member,
                                isSelected: selectedMemberDIDs.contains(member.did),
                                onToggle: {
                                    toggleSelection(member.did)
                                }
                            )
                        }
                    }
                    .padding()
                }

                // Error message
                if let shareError = shareError {
                    Text(shareError)
                        .font(.budsCaption)
                        .foregroundColor(.budsDanger)
                        .padding()
                }

                // Share button
                Button(action: shareMemory) {
                    if shareManager.isSharing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text("Share (\(selectedMemberDIDs.count) members)")
                            .font(.budsBodyBold)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(selectedMemberDIDs.isEmpty ? Color.budsTextSecondary : Color.budsPrimary)
                .cornerRadius(12)
                .disabled(selectedMemberDIDs.isEmpty || shareManager.isSharing)
                .padding()
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ did: String) {
        if selectedMemberDIDs.contains(did) {
            selectedMemberDIDs.remove(did)
        } else {
            selectedMemberDIDs.insert(did)
        }
    }

    private func shareMemory() {
        shareError = nil

        Task {
            do {
                try await shareManager.shareMemory(
                    memoryCID: memoryCID,
                    with: Array(selectedMemberDIDs)
                )
                dismiss()
            } catch {
                shareError = error.localizedDescription
            }
        }
    }
}

// MARK: - Member Selection Row

struct MemberSelectionRow: View {
    let member: CircleMember
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Circle()
                .fill(Color.budsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(member.displayName.prefix(1).uppercased())
                        .font(.budsHeadline)
                        .foregroundColor(.budsPrimary)
                )

            // Name
            Text(member.displayName)
                .font(.budsBodyBold)
                .foregroundColor(.white)

            Spacer()

            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .budsPrimary : .budsTextSecondary)
                .font(.title2)
        }
        .padding()
        .background(Color.budsCard)
        .cornerRadius(12)
        .onTapGesture {
            onToggle()
        }
    }
}

#Preview {
    ShareToCircleView(memoryCID: "bafyreiabc123")
}
```

---

## Testing Checkpoints

### Checkpoint 1: Cloudflare Workers Setup
- ✅ Workers project created and deployed
- ✅ D1 database initialized with schema
- ✅ Local dev server runs: `npm run dev`
- ✅ Health check works: `curl http://localhost:8787/health`

### Checkpoint 2: Device Registration
- ✅ App launches and registers device on first sign-in
- ✅ Console shows "✅ Device registered: [deviceId]"
- ✅ D1 database → `devices` table has entry
- ✅ `phone_to_did` table maps phone → DID

### Checkpoint 3: Circle Member Lookup
- ✅ Add Circle member with real phone number (must be registered user)
- ✅ Sees real DID (not placeholder)
- ✅ Member shows "active" status
- ✅ Console shows "✅ Added Circle member: [name]"

### Checkpoint 4: E2EE Encryption
- ✅ Share memory to 1 Circle member
- ✅ Console shows encryption process (key wrapping, device lookup)
- ✅ D1 → `encrypted_messages` table has entry
- ✅ `encrypted_payload` and `wrapped_keys` are base64 strings

### Checkpoint 5: Message Delivery (Manual Test)
- ✅ Recipient polls inbox: GET `/api/messages/inbox?did=xxx`
- ✅ Receives encrypted message
- ✅ Successfully decrypts and displays memory
- ✅ `message_delivery` table marks as delivered

---

## Troubleshooting

### Cloudflare Workers Errors

**"Binding DB is not defined"**
→ Check `wrangler.toml` has correct D1 binding and database ID

**"Failed to execute query"**
→ Run schema migration: `npx wrangler d1 execute buds-relay-db --remote --file=schema.sql`

**"CORS error"**
→ Check CORS middleware in `src/index.ts` allows your app domain

### Swift Build Errors

**"Cannot find 'RelayClient' in scope"**
→ Add `RelayClient.swift` to Xcode project target

**"Ambiguous use of 'seal'"**
→ Make sure you're importing `CryptoKit`, not a conflicting crypto library

### Runtime Errors

**"Device not registered"**
→ Call `DeviceManager.shared.registerDevice()` after sign-in

**"No key for device"**
→ Recipient device wasn't included in encryption (check device lookup logic)

**"User not found"**
→ Phone number hasn't registered with Buds yet (expected for new users)

**"Invalid token"**
→ Firebase Auth token expired, re-authenticate

---

## What's Next (Phase 7+)

Phase 7 will add:
1. **Message Inbox** - View received shared memories
2. **Map View** - Visualize memories with fuzzy location
3. **Push Notifications** - Real-time delivery via APNs
4. **Background Sync** - Periodic polling for new messages

**For now:** Phase 6 creates the E2EE foundation with Cloudflare Workers relay.

---

## Summary

**Cloudflare Workers (TypeScript):**
- `src/index.ts` - Main router (~50 lines)
- `src/handlers/devices.ts` - Device registration (~120 lines)
- `src/handlers/lookup.ts` - DID lookup (~60 lines)
- `src/handlers/messages.ts` - Message send/receive (~150 lines)
- `src/utils/auth.ts` - Firebase token verification (~40 lines)
- `src/utils/crypto.ts` - Phone hashing (~20 lines)
- **Total:** ~440 lines TypeScript

**Swift Components:**
- `Core/RelayClient.swift` (~250 lines)
- `Core/DeviceManager.swift` (~150 lines)
- `Core/E2EEManager.swift` (~200 lines)
- `Core/ShareManager.swift` (~80 lines)
- `Core/Models/EncryptedMessage.swift` (~25 lines)
- `Features/Share/ShareToCircleView.swift` (~150 lines)
- **Total:** ~855 lines Swift

**Files Modified (3):**
- `Core/ChaingeKernel/IdentityManager.swift` (+30 lines: device ID, X25519 keypair)
- `Core/CircleManager.swift` (+30 lines: real DID lookup)
- `Features/Timeline/MemoryDetailView.swift` (+15 lines: share button)
- `BudsApp.swift` (+5 lines: device registration on launch)

**Infrastructure:**
- Cloudflare Workers relay (edge compute)
- D1 database (SQLite at the edge)
- Firebase Auth only (phone verification)

**Estimated Time:** 10-14 hours (includes Workers setup + testing)

**Next Steps:** Test E2EE flow end-to-end, then proceed to Phase 7 (message inbox + push notifications).

---

**December 20, 2025: Ready to implement Phase 6 with Cloudflare Workers! Let's build the relay. 🔐🌿**
