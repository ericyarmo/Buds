#!/usr/bin/env python3
"""
Single-Device E2EE Test Harness
================================

Tests Phase 7 E2EE flow with just ONE physical device by simulating a second device.

Architecture:
- Device A: Real iPhone (sender)
- Device B: Simulated via this script (receiver)

Flow:
1. Script registers fake Device B to relay
2. iPhone shares memory (triggers relay upload)
3. Script polls inbox for Device B
4. Script decrypts message and verifies signature
5. Script validates CID integrity

Requirements:
- pip install cryptography requests
- Firebase ID token from iPhone (copy from Xcode logs)
"""

import json
import base64
import hashlib
import secrets
from typing import Dict, Tuple
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
import requests

# Configuration
RELAY_URL = "https://buds-relay.getstreams.workers.dev"  # Buds relay server
FIREBASE_ID_TOKEN = "eyJhbGciOiJSUzI1NiIsImtpZCI6Ijk4OGQ1YTM3OWI3OGJkZjFlNTBhNDA5MTEzZjJiMGM3NWU0NTJlNDciLCJ0eXAiOiJKV1QifQ.eyJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vYnVkcy1hMzJlMCIsImF1ZCI6ImJ1ZHMtYTMyZTAiLCJhdXRoX3RpbWUiOjE3NjYxNjk4MjUsInVzZXJfaWQiOiJGTHJwQ0FIMVJ4VjFFT3FKdU9tWlozSGdWdlEyIiwic3ViIjoiRkxycENBSDFSeFYxRU9xSnVPbVpaM0hnVnZRMiIsImlhdCI6MTc2NjY0OTAzNSwiZXhwIjoxNzY2NjUyNjM1LCJwaG9uZV9udW1iZXIiOiIrMTY1MDQ0NTg5ODgiLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7InBob25lIjpbIisxNjUwNDQ1ODk4OCJdfSwic2lnbl9pbl9wcm92aWRlciI6InBob25lIn19.DE89-UrcQ6vVewztlXGfwV4-ZDEQK9TxcbvkAzELFWSvD6U1SJbpfg8O880OgCQ2cFS0Q2EibtjCxgP8wbpAi8UN1HYaVrcVWoHy_GeodjQ7OlHb6-1DiveihjtwZ5sCoE3ZsXX4cXUc8Ch46A32zZCOjqojXLG8INjn7VOyBrbZiR-f7KIa9bYHpCd0F7fLB664B5QsLTjTpW0ijesFaK2A-v9me1_H9wWmRaLVv0uhXy62fFsP74ug8bLzG4dafSlhuGBMJcAkxKqsYqpvckq7D9OEnkeh0L8dInmExTNFqR8Md0PYaMSx01qlG6nvxU2jkQfhrkDY7vhBc0a8kQ" # from Xcode logs after running the app!
                          # Look for: "🔐 Firebase ID Token: eyJhbGci..." (long JWT string)

# Your info (will be used as defaults if not provided at runtime)
DEFAULT_YOUR_DID = "did:buds:3mVJmCTSNQf1VRQZmwsNHvJLYHaA"  # Your iPhone's DID (sender)
DEFAULT_YOUR_PHONE = "+16504458988"  # Your phone number

# Simulated friend's info (receiver - Device B)
# This will be auto-generated with a random DID
SIMULATED_FRIEND_PHONE = "+15555551234"  # Fake phone number for testing

class SimulatedDevice:
    """Simulates a receiving device for E2EE testing"""

    def __init__(self, did: str, device_name: str = "Test Device B"):
        self.did = did
        self.device_id = self._generate_uuid()
        self.device_name = device_name

        # Generate keypairs
        self.x25519_private = X25519PrivateKey.generate()
        self.x25519_public = self.x25519_private.public_key()
        self.ed25519_private = Ed25519PrivateKey.generate()
        self.ed25519_public = self.ed25519_private.public_key()

        print(f"📱 Simulated Device Created:")
        print(f"   DID: {did}")
        print(f"   Device ID: {self.device_id}")
        print(f"   X25519 Public: {self._b64(self.x25519_public.public_bytes_raw())[:20]}...")
        print(f"   Ed25519 Public: {self._b64(self.ed25519_public.public_bytes_raw())[:20]}...")

    def register_to_relay(self, firebase_token: str, phone_hash: str) -> Dict:
        """Register this simulated device to the relay"""
        payload = {
            "device_id": self.device_id,
            "device_name": self.device_name,
            "owner_did": self.did,
            "owner_phone_hash": phone_hash,
            "pubkey_x25519": self._b64(self.x25519_public.public_bytes_raw()),
            "pubkey_ed25519": self._b64(self.ed25519_public.public_bytes_raw())
        }

        headers = {
            "Authorization": f"Bearer {firebase_token}",
            "Content-Type": "application/json"
        }

        print(f"\n📡 Registering device to relay...")
        response = requests.post(
            f"{RELAY_URL}/api/devices/register",
            json=payload,
            headers=headers
        )

        if response.status_code == 201:
            print(f"✅ Device registered successfully")
            return response.json()
        else:
            print(f"❌ Registration failed: {response.status_code}")
            print(f"   Response: {response.text}")
            raise Exception("Device registration failed")

    def poll_inbox(self, firebase_token: str) -> list:
        """Poll relay inbox for new messages"""
        headers = {
            "Authorization": f"Bearer {firebase_token}",
        }

        print(f"\n📬 Polling inbox for {self.did}...")
        response = requests.get(
            f"{RELAY_URL}/api/messages/inbox?did={self.did}&limit=50",
            headers=headers
        )

        if response.status_code == 200:
            data = response.json()
            count = data.get('count', 0)
            print(f"📭 Found {count} messages")
            return data.get('messages', [])
        else:
            print(f"❌ Inbox poll failed: {response.status_code}")
            print(f"   Response: {response.text}")
            return []

    def decrypt_message(self, message: Dict) -> Dict:
        """Decrypt E2EE message and verify integrity"""
        print(f"\n🔓 Decrypting message {message['message_id'][:8]}...")
        print(f"   Sender: {message['sender_did']}")
        print(f"   Receipt CID: {message['receipt_cid'][:20]}...")

        # Step 1: Unwrap AES key using X25519
        wrapped_key_b64 = message['wrapped_keys'].get(self.device_id)
        if not wrapped_key_b64:
            raise Exception(f"No wrapped key found for device {self.device_id}")

        wrapped_key = base64.b64decode(wrapped_key_b64)
        print(f"🔑 Wrapped key size: {len(wrapped_key)} bytes")

        # Parse wrapped key: sender_ephemeral_pubkey (32) + nonce (12) + ciphertext (32) + tag (16)
        sender_ephemeral_pubkey_bytes = wrapped_key[:32]
        nonce = wrapped_key[32:44]
        ciphertext_tag = wrapped_key[44:]

        # ECDH to derive shared secret
        from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PublicKey
        sender_ephemeral_pubkey = X25519PublicKey.from_public_bytes(sender_ephemeral_pubkey_bytes)
        shared_secret = self.x25519_private.exchange(sender_ephemeral_pubkey)

        # HKDF to derive KEK
        kek = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=None,
            info=b"BudsE2EE-KeyWrap"
        ).derive(shared_secret)

        # Decrypt wrapped key
        aesgcm = AESGCM(kek)
        aes_key = aesgcm.decrypt(nonce, ciphertext_tag, None)
        print(f"✅ Unwrapped AES key: {len(aes_key)} bytes")

        # Step 2: Decrypt payload with AES-256-GCM
        encrypted_payload = base64.b64decode(message['encrypted_payload'])
        payload_nonce = encrypted_payload[:12]
        payload_ciphertext_tag = encrypted_payload[12:]

        aesgcm_payload = AESGCM(aes_key)
        raw_cbor = aesgcm_payload.decrypt(payload_nonce, payload_ciphertext_tag, None)
        print(f"✅ Decrypted payload: {len(raw_cbor)} bytes CBOR")

        # Step 3: Verify CID integrity
        computed_cid = self._compute_cid(raw_cbor)
        claimed_cid = message['receipt_cid']

        if computed_cid != claimed_cid:
            print(f"❌ CID MISMATCH!")
            print(f"   Expected: {claimed_cid}")
            print(f"   Computed: {computed_cid}")
            raise Exception("CID integrity check failed - tampering detected!")

        print(f"✅ CID verified - content integrity confirmed")

        # Step 4: Verify Ed25519 signature
        # NOTE: We'd need sender's Ed25519 public key from Circle roster
        # For now, just decode signature to validate format
        signature_bytes = base64.b64decode(message['signature'])
        print(f"🔐 Signature size: {len(signature_bytes)} bytes (expected: 64)")

        if len(signature_bytes) != 64:
            raise Exception(f"Invalid signature length: {len(signature_bytes)}")

        print(f"✅ Signature format valid (full verification requires sender's public key)")

        return {
            'raw_cbor': raw_cbor,
            'cid': computed_cid,
            'signature': signature_bytes,
            'sender_did': message['sender_did'],
            'sender_device_id': message['sender_device_id']
        }

    def delete_message(self, message_id: str, firebase_token: str):
        """Mark message as delivered and delete from relay"""
        headers = {
            "Authorization": f"Bearer {firebase_token}",
        }

        print(f"\n🗑️  Deleting message from relay...")
        response = requests.delete(
            f"{RELAY_URL}/api/messages/{message_id}",
            headers=headers
        )

        if response.status_code == 200:
            print(f"✅ Message deleted")
        else:
            print(f"⚠️  Delete failed: {response.status_code}")

    # Helpers

    def _generate_uuid(self) -> str:
        """Generate UUID v4"""
        import uuid
        return str(uuid.uuid4())

    def _b64(self, data: bytes) -> str:
        """Base64 encode"""
        return base64.b64encode(data).decode('ascii')

    def _compute_cid(self, cbor_data: bytes) -> str:
        """Compute CIDv1 from CBOR (matches Swift implementation)"""
        # SHA-256 hash
        hash_bytes = hashlib.sha256(cbor_data).digest()

        # Multihash: 0x12 (sha2-256) + 0x20 (32 bytes) + hash
        multihash = bytes([0x12, 0x20]) + hash_bytes

        # CIDv1: 0x01 (version) + 0x71 (dag-cbor) + multihash
        cid_bytes = bytes([0x01, 0x71]) + multihash

        # Base32 encode (lowercase)
        import base64
        b32 = base64.b32encode(cid_bytes).decode('ascii').lower().rstrip('=')

        return f"b{b32}"


def hash_phone_number(phone: str) -> str:
    """Hash phone number with SHA-256 (matches relay implementation)"""
    # IMPORTANT: Relay hashes phone number AS-IS (including + sign)
    # This must match the format Firebase provides in the JWT token
    hash_bytes = hashlib.sha256(phone.encode('utf-8')).digest()
    return hash_bytes.hex()


def main():
    """Run single-device E2EE test"""

    print("=" * 70)
    print("Phase 7 E2EE Single-Device Test Harness")
    print("=" * 70)

    if not FIREBASE_ID_TOKEN:
        print("\n❌ ERROR: FIREBASE_ID_TOKEN not set!")
        print("   1. Run the app on your iPhone")
        print("   2. Look for '🔐 Firebase ID Token:' in Xcode logs")
        print("   3. Copy the token and paste it in this script")
        return

    # Test configuration (use defaults or prompt)
    YOUR_DID = DEFAULT_YOUR_DID
    YOUR_PHONE = DEFAULT_YOUR_PHONE

    print(f"\n📝 Using DID: {YOUR_DID}")
    print(f"📝 Using Phone: {YOUR_PHONE}")

    phone_hash = hash_phone_number(YOUR_PHONE)
    print(f"📞 Phone hash: {phone_hash[:20]}...")

    # Create simulated Device B
    device_b = SimulatedDevice(did=YOUR_DID, device_name="Test Device B (Python)")

    # Register Device B to relay
    try:
        device_b.register_to_relay(FIREBASE_ID_TOKEN, phone_hash)
    except Exception as e:
        print(f"\n❌ Test failed at registration: {e}")
        return

    # Wait for user to share a memory from iPhone
    print("\n" + "=" * 70)
    print("⏸️  PAUSE: Go to your iPhone and share a memory")
    print("   (This will send to all your devices, including Device B)")
    print("=" * 70)
    input("Press Enter when you've shared a memory...")

    # Poll inbox
    messages = device_b.poll_inbox(FIREBASE_ID_TOKEN)

    if not messages:
        print("\n❌ No messages found. Did you share the memory?")
        return

    # Find message with wrapped key for Device B (skip old messages)
    print(f"\n📋 Found {len(messages)} messages, looking for one with Device B's key...")
    target_message = None
    for msg in messages:
        if device_b.device_id in msg.get('wrapped_keys', {}):
            target_message = msg
            print(f"✅ Found message with Device B's wrapped key!")
            break

    if not target_message:
        print(f"\n❌ No messages found with Device B's wrapped key")
        print(f"   Device B ID: {device_b.device_id}")
        print(f"   This means the iPhone hasn't sent a NEW memory since Device B registered")
        print(f"   Please share a memory NOW from iPhone and run the test again")
        return

    # Decrypt the message
    try:
        result = device_b.decrypt_message(target_message)
        print("\n" + "=" * 70)
        print("✅ E2EE TEST PASSED!")
        print("=" * 70)
        print(f"   CID: {result['cid'][:30]}...")
        print(f"   CBOR size: {len(result['raw_cbor'])} bytes")
        print(f"   Sender: {result['sender_did']}")
        print(f"   Sender device: {result['sender_device_id']}")

        # Clean up
        device_b.delete_message(target_message['message_id'], FIREBASE_ID_TOKEN)

    except Exception as e:
        print(f"\n❌ Decryption failed: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
