#!/bin/bash
# Quick test runner for E2EE single-device test

echo "======================================================================"
echo "Phase 7 E2EE Test - Setup"
echo "======================================================================"
echo ""
echo "STEP 1: Get Firebase ID Token from iPhone"
echo "-------------------------------------------"
echo "1. Open Xcode and run Buds app on your iPhone"
echo "2. In Xcode console, look for a line like:"
echo "   🔐 Firebase ID Token: eyJhbGciOiJSUzI1NiIsImtpZCI6Ij..."
echo "3. Copy the FULL token (starts with 'eyJ', ~800 characters)"
echo ""
echo -n "Paste Firebase ID Token here: "
read FIREBASE_TOKEN

echo ""
echo "STEP 2: Update test script"
echo "-------------------------------------------"

# Use sed to update the token in the test file
sed -i '' "s/FIREBASE_ID_TOKEN = None/FIREBASE_ID_TOKEN = \"$FIREBASE_TOKEN\"/" test_e2ee_single_device.py

echo "✅ Token updated in test_e2ee_single_device.py"
echo ""
echo "STEP 3: Run the test"
echo "-------------------------------------------"
echo "The test will:"
echo "  1. Register a simulated Device B to the relay"
echo "  2. Wait for you to share a memory from iPhone"
echo "  3. Poll inbox and decrypt the message"
echo "  4. Verify CID integrity and signature"
echo ""
echo "Press Enter to start the test..."
read

# Activate venv and run test
source venv/bin/activate
python3 test_e2ee_single_device.py

echo ""
echo "======================================================================"
echo "Test complete!"
echo "======================================================================"
