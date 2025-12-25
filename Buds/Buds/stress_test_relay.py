#!/usr/bin/env python3
"""
Relay Stress Test
==================

Simulates 1000 users sending 10,000 messages/day to test relay performance.

Tests:
- D1 write throughput (message inserts)
- D1 read throughput (inbox queries)
- Worker CPU under load
- Rate limiting effectiveness
- APNs delivery (if configured)

Requirements:
- pip install requests asyncio aiohttp
- Firebase ID token
"""

import asyncio
import aiohttp
import time
import random
import hashlib
import base64
from typing import List, Dict
from dataclasses import dataclass
from collections import defaultdict

# Configuration
RELAY_URL = "https://buds-relay-production.ericyarmolinsky.workers.dev"
FIREBASE_ID_TOKEN = None  # Paste from Xcode logs

# Test parameters
NUM_USERS = 100  # Simulated users (start small, scale up)
NUM_MESSAGES = 1000  # Total messages to send
CONCURRENCY = 10  # Parallel requests
INBOX_POLL_INTERVAL = 5  # Seconds between inbox polls


@dataclass
class SimUser:
    """Simulated user"""
    did: str
    device_id: str
    phone_hash: str
    pubkey_x25519: str
    pubkey_ed25519: str


class RelayStressTester:
    """Stress test harness for Buds relay"""

    def __init__(self, relay_url: str, firebase_token: str):
        self.relay_url = relay_url
        self.firebase_token = firebase_token
        self.users: List[SimUser] = []
        self.metrics = {
            'register_success': 0,
            'register_failed': 0,
            'send_success': 0,
            'send_failed': 0,
            'inbox_success': 0,
            'inbox_failed': 0,
            'total_latency': defaultdict(list),
        }

    async def setup_users(self, num_users: int):
        """Create and register simulated users"""
        print(f"📝 Creating {num_users} simulated users...")

        tasks = []
        for i in range(num_users):
            user = SimUser(
                did=f"did:buds:test{i:05d}",
                device_id=self._uuid(),
                phone_hash=self._hash_phone(f"+1555000{i:04d}"),
                pubkey_x25519=self._random_b64(32),
                pubkey_ed25519=self._random_b64(32)
            )
            self.users.append(user)
            tasks.append(self.register_user(user))

        # Register users in parallel
        start = time.time()
        results = await asyncio.gather(*tasks, return_exceptions=True)
        elapsed = time.time() - start

        success = sum(1 for r in results if not isinstance(r, Exception))
        failed = len(results) - success

        print(f"✅ Registered {success}/{num_users} users in {elapsed:.2f}s")
        if failed > 0:
            print(f"❌ {failed} registrations failed")

    async def register_user(self, user: SimUser):
        """Register a single user"""
        payload = {
            "device_id": user.device_id,
            "device_name": f"Test Device {user.did[-5:]}",
            "owner_did": user.did,
            "owner_phone_hash": user.phone_hash,
            "pubkey_x25519": user.pubkey_x25519,
            "pubkey_ed25519": user.pubkey_ed25519
        }

        async with aiohttp.ClientSession() as session:
            headers = {"Authorization": f"Bearer {self.firebase_token}"}
            start = time.time()

            try:
                async with session.post(
                    f"{self.relay_url}/api/devices/register",
                    json=payload,
                    headers=headers
                ) as resp:
                    latency = (time.time() - start) * 1000
                    self.metrics['total_latency']['register'].append(latency)

                    if resp.status == 201:
                        self.metrics['register_success'] += 1
                        return True
                    else:
                        self.metrics['register_failed'] += 1
                        print(f"❌ Register failed: {resp.status}")
                        return False

            except Exception as e:
                self.metrics['register_failed'] += 1
                print(f"❌ Register error: {e}")
                return False

    async def send_message(self, sender: SimUser, recipients: List[SimUser]):
        """Send E2EE message"""
        message_id = self._uuid()
        receipt_cid = f"bafyrei{self._random_b64(30).lower()}"

        # Simulate wrapped keys (one per recipient device)
        wrapped_keys = {
            r.device_id: self._random_b64(92)
            for r in recipients
        }

        payload = {
            "message_id": message_id,
            "receipt_cid": receipt_cid,
            "sender_did": sender.did,
            "sender_device_id": sender.device_id,
            "recipient_dids": [r.did for r in recipients],
            "encrypted_payload": self._random_b64(700),  # ~500 KB encrypted
            "wrapped_keys": wrapped_keys,
            "signature": self._random_b64(88)  # Ed25519 signature
        }

        async with aiohttp.ClientSession() as session:
            headers = {"Authorization": f"Bearer {self.firebase_token}"}
            start = time.time()

            try:
                async with session.post(
                    f"{self.relay_url}/api/messages/send",
                    json=payload,
                    headers=headers
                ) as resp:
                    latency = (time.time() - start) * 1000
                    self.metrics['total_latency']['send'].append(latency)

                    if resp.status == 201:
                        self.metrics['send_success'] += 1
                        return True
                    else:
                        self.metrics['send_failed'] += 1
                        text = await resp.text()
                        print(f"❌ Send failed: {resp.status} - {text[:100]}")
                        return False

            except Exception as e:
                self.metrics['send_failed'] += 1
                print(f"❌ Send error: {e}")
                return False

    async def poll_inbox(self, user: SimUser):
        """Poll inbox for new messages"""
        async with aiohttp.ClientSession() as session:
            headers = {"Authorization": f"Bearer {self.firebase_token}"}
            start = time.time()

            try:
                async with session.get(
                    f"{self.relay_url}/api/messages/inbox?did={user.did}&limit=50",
                    headers=headers
                ) as resp:
                    latency = (time.time() - start) * 1000
                    self.metrics['total_latency']['inbox'].append(latency)

                    if resp.status == 200:
                        self.metrics['inbox_success'] += 1
                        data = await resp.json()
                        return data.get('messages', [])
                    else:
                        self.metrics['inbox_failed'] += 1
                        return []

            except Exception as e:
                self.metrics['inbox_failed'] += 1
                print(f"❌ Inbox error: {e}")
                return []

    async def stress_test_sends(self, num_messages: int, concurrency: int):
        """Send messages with controlled concurrency"""
        print(f"\n📤 Sending {num_messages} messages (concurrency: {concurrency})...")

        semaphore = asyncio.Semaphore(concurrency)
        tasks = []

        async def send_with_limit():
            async with semaphore:
                sender = random.choice(self.users)
                # Simulate Circle size: 2-12 members
                circle_size = random.randint(2, min(12, len(self.users)))
                recipients = random.sample(self.users, circle_size)
                return await self.send_message(sender, recipients)

        start = time.time()
        tasks = [send_with_limit() for _ in range(num_messages)]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        elapsed = time.time() - start

        success = sum(1 for r in results if r is True)
        print(f"✅ Sent {success}/{num_messages} messages in {elapsed:.2f}s")
        print(f"   Throughput: {success/elapsed:.2f} msg/s")

    async def stress_test_inbox_polling(self, duration_seconds: int):
        """Poll all user inboxes continuously"""
        print(f"\n📬 Polling {len(self.users)} inboxes for {duration_seconds}s...")

        start = time.time()
        total_polls = 0

        while time.time() - start < duration_seconds:
            tasks = [self.poll_inbox(user) for user in self.users]
            await asyncio.gather(*tasks, return_exceptions=True)
            total_polls += len(self.users)
            await asyncio.sleep(INBOX_POLL_INTERVAL)

        elapsed = time.time() - start
        print(f"✅ Completed {total_polls} inbox polls in {elapsed:.2f}s")
        print(f"   Throughput: {total_polls/elapsed:.2f} polls/s")

    def print_metrics(self):
        """Print test metrics"""
        print("\n" + "=" * 70)
        print("STRESS TEST RESULTS")
        print("=" * 70)

        # Success rates
        print("\n📊 Success Rates:")
        print(f"   Register: {self.metrics['register_success']}/{self.metrics['register_success'] + self.metrics['register_failed']}")
        print(f"   Send:     {self.metrics['send_success']}/{self.metrics['send_success'] + self.metrics['send_failed']}")
        print(f"   Inbox:    {self.metrics['inbox_success']}/{self.metrics['inbox_success'] + self.metrics['inbox_failed']}")

        # Latency percentiles
        print("\n⏱️  Latency (ms):")
        for op, latencies in self.metrics['total_latency'].items():
            if not latencies:
                continue

            latencies.sort()
            p50 = latencies[len(latencies) // 2]
            p95 = latencies[int(len(latencies) * 0.95)]
            p99 = latencies[int(len(latencies) * 0.99)]
            avg = sum(latencies) / len(latencies)

            print(f"   {op.capitalize():10} - avg: {avg:6.2f}ms  p50: {p50:6.2f}ms  p95: {p95:6.2f}ms  p99: {p99:6.2f}ms")

        print("\n" + "=" * 70)

    # Helpers

    def _uuid(self) -> str:
        import uuid
        return str(uuid.uuid4())

    def _random_b64(self, byte_length: int) -> str:
        import os
        return base64.b64encode(os.urandom(byte_length)).decode('ascii')

    def _hash_phone(self, phone: str) -> str:
        """SHA-256 hash of phone number"""
        digits = ''.join(c for c in phone if c.isdigit())
        if len(digits) == 10:
            digits = '1' + digits
        return hashlib.sha256(digits.encode()).hexdigest()


async def main():
    """Run stress tests"""

    print("=" * 70)
    print("Buds Relay Stress Test")
    print("=" * 70)

    if not FIREBASE_ID_TOKEN:
        print("\n❌ ERROR: FIREBASE_ID_TOKEN not set!")
        return

    tester = RelayStressTester(RELAY_URL, FIREBASE_ID_TOKEN)

    # Phase 1: Register users
    await tester.setup_users(NUM_USERS)

    # Phase 2: Stress test message sending
    await tester.stress_test_sends(NUM_MESSAGES, CONCURRENCY)

    # Phase 3: Stress test inbox polling
    await tester.stress_test_inbox_polling(duration_seconds=30)

    # Print metrics
    tester.print_metrics()

    print("\n✅ Stress test complete!")


if __name__ == "__main__":
    asyncio.run(main())
