import XCTest
@testable import BudsKernelGolden
import CryptoKit

final class TamperTests: XCTestCase {

  func testTamperOneByteBreaksCID() throws {
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
    let cid1 = CID.computeCIDv1DagCBORSha256(preimage)

    var tampered = preimage
    tampered[tampered.startIndex] ^= 0x01

    let cid2 = CID.computeCIDv1DagCBORSha256(tampered)
    XCTAssertNotEqual(cid1, cid2)
  }

  func testTamperOneByteBreaksSignatureVerification() throws {
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

    let skRaw = Data(repeating: 0x11, count: 32)
    let pkRaw = try Curve25519.Signing.PrivateKey(rawRepresentation: skRaw).publicKey.rawRepresentation
    let sig = try Signing.signEd25519(preimage: preimage, privateKeyRaw32: skRaw)

    var tampered = preimage
    tampered[tampered.startIndex] ^= 0x01

    XCTAssertTrue(Signing.verifyEd25519(preimage: preimage, signature: sig, publicKeyRaw32: pkRaw))
    XCTAssertFalse(Signing.verifyEd25519(preimage: tampered, signature: sig, publicKeyRaw32: pkRaw))
  }
}
