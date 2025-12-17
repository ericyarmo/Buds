import XCTest
@testable import BudsKernelGolden
import CryptoKit

final class GoldenVectorTests: XCTestCase {

  func testVector1_MatchesFixtures() throws {
    // Load input unsigned receipt JSON from disk
    let jsonData = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let unsigned = try JSONDecoder().decode(UnsignedReceipt.self, from: jsonData)

    // Canonicalize to raw CBOR bytes
    let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
    let cid = CID.computeCIDv1DagCBORSha256(preimage)

    // Fixed signing key (deterministic key; signature bytes may still vary in CryptoKit)
    let skRaw = Data(repeating: 0x11, count: 32)
    let sk = try Curve25519.Signing.PrivateKey(rawRepresentation: skRaw)
    let pkRaw = sk.publicKey.rawRepresentation

    let sig = try Signing.signEd25519(preimage: preimage, privateKeyRaw32: skRaw)

    // Verify signature properties (don’t byte-match fixture)
    XCTAssertEqual(sig.count, 64, "Ed25519 signatures should be 64 bytes")
    XCTAssertTrue(Signing.verifyEd25519(preimage: preimage, signature: sig, publicKeyRaw32: pkRaw))

    // Expected fixtures from disk
    let expectedCBORHex = try TestFixtures.string(name: "vector1_expected", ext: "cbor.hex")
    let expectedCID = try TestFixtures.string(name: "vector1_expected", ext: "cid")

    XCTAssertEqual(Hex.encode(preimage), expectedCBORHex, "CBOR hex mismatch")
    XCTAssertEqual(cid, expectedCID, "CID mismatch")
  }
}

