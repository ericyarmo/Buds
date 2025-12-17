import XCTest
@testable import BudsKernelGolden
import CryptoKit

final class FullPipelineTests: XCTestCase {

  func testFullPipeline_WrapSeal_UnwrapOpen_Verify() throws {
    // 1) Build receipt bytes + CID
    let jsonData = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let unsigned = try JSONDecoder().decode(UnsignedReceipt.self, from: jsonData)

    let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
    let cid = CID.computeCIDv1DagCBORSha256(preimage)

    // 2) Sign the receipt bytes (author key)
    let authorSKRaw = Data(repeating: 0x11, count: 32)
    let authorSK = try Curve25519.Signing.PrivateKey(rawRepresentation: authorSKRaw)
    let authorPKRaw = authorSK.publicKey.rawRepresentation
    let sig = try Signing.signEd25519(preimage: preimage, privateKeyRaw32: authorSKRaw)

    XCTAssertTrue(Signing.verifyEd25519(preimage: preimage, signature: sig, publicKeyRaw32: authorPKRaw))

    // 3) Generate content key and encrypt receipt bytes using AAD = CID
    let contentKey = SymmetricKey(size: .bits256)
    let combined = try Envelope.seal(plaintext: preimage, contentKey: contentKey, aadCID: cid)

    // 4) Recipient device keypair
    let recipientSK = Curve25519.KeyAgreement.PrivateKey()
    let recipientPKRaw = recipientSK.publicKey.rawRepresentation

    // Convert SymmetricKey -> raw bytes so we can wrap
    let contentKeyRaw = contentKey.withUnsafeBytes { Data($0) }
    XCTAssertEqual(contentKeyRaw.count, 32)

    // 5) Wrap content key for recipient
    let (ephPub, wrapped) = try KeyWrap.wrapContentKeyForRecipient(
      contentKeyRaw32: contentKeyRaw,
      recipientPublicKeyRaw32: recipientPKRaw
    )

    // 6) Recipient unwraps content key
    let unwrappedRaw = try KeyWrap.unwrapContentKeyForRecipient(
      ephemeralPublicKeyRaw32: ephPub,
      wrappedCombined: wrapped,
      recipientPrivateKey: recipientSK
    )
    let unwrappedKey = SymmetricKey(data: unwrappedRaw)

    // 7) Recipient decrypts payload with same AAD
    let opened = try Envelope.open(combined: combined, contentKey: unwrappedKey, aadCID: cid)
    XCTAssertEqual(opened, preimage)

    // 8) Verify CID recomputes identically
    let cid2 = CID.computeCIDv1DagCBORSha256(opened)
    XCTAssertEqual(cid2, cid)

    // 9) Verify author signature still checks out on decrypted bytes
    XCTAssertTrue(Signing.verifyEd25519(preimage: opened, signature: sig, publicKeyRaw32: authorPKRaw))
  }
}
