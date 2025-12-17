//
//  FixtureGeneratorTests.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//


import XCTest
@testable import BudsKernelGolden

final class FixtureGeneratorTests: XCTestCase {

  func testGenerateVector1Outputs_PrintOnly() throws {
    let payload = SessionPayload(
      claimed_time_ms: 1704844800000,
      product_name: "Blue Dream",
      strain_type: "hybrid",
      notes: "Great for focus",
      rating: 5
    )

    let unsigned = UnsignedReceipt(
      did: "did:buds:local-ABC123",
      deviceId: "device-001",
      parentCID: nil,
      rootCID: nil,
      receiptType: "app.buds.session.created/v1",
      payload: payload
    )

    let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
    let cid = CID.computeCIDv1DagCBORSha256(preimage)

    let skRaw = Data(repeating: 0x11, count: 32)
    let sig = try Signing.signEd25519(preimage: preimage, privateKeyRaw32: skRaw)

    print("=== VECTOR1 GENERATED ===")
    print("vector1_expected.cbor.hex:\n\(Hex.encode(preimage))")
    print("vector1_expected.cid:\n\(cid)")
    print("vector1_expected.sig.b64:\n\(sig.base64EncodedString())")
  }
}
