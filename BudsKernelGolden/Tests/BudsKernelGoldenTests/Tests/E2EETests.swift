//
//  E2EETests.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import XCTest
@testable import BudsKernelGolden
import CryptoKit

final class E2EETests: XCTestCase {

  func testSealOpen_RoundTrip_RawCBOR() throws {
    let jsonData = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let unsigned = try JSONDecoder().decode(UnsignedReceipt.self, from: jsonData)

    let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
    let cid = CID.computeCIDv1DagCBORSha256(preimage)

    let key = SymmetricKey(size: .bits256)

    let combined = try Envelope.seal(plaintext: preimage, contentKey: key, aadCID: cid)
    let opened = try Envelope.open(combined: combined, contentKey: key, aadCID: cid)

    XCTAssertEqual(opened, preimage, "Decrypted bytes must match original raw CBOR")
  }

  func testOpen_Fails_WithWrongAAD() throws {
    let jsonData = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let unsigned = try JSONDecoder().decode(UnsignedReceipt.self, from: jsonData)

    let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
    let cid = CID.computeCIDv1DagCBORSha256(preimage)

    let key = SymmetricKey(size: .bits256)

    let combined = try Envelope.seal(plaintext: preimage, contentKey: key, aadCID: cid)

    XCTAssertThrowsError(
      try Envelope.open(combined: combined, contentKey: key, aadCID: cid + "tamper")
    )
  }

  func testOpen_Fails_WithWrongKey() throws {
    let jsonData = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let unsigned = try JSONDecoder().decode(UnsignedReceipt.self, from: jsonData)

    let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
    let cid = CID.computeCIDv1DagCBORSha256(preimage)

    let keyGood = SymmetricKey(size: .bits256)
    let keyBad  = SymmetricKey(size: .bits256)

    let combined = try Envelope.seal(plaintext: preimage, contentKey: keyGood, aadCID: cid)

    XCTAssertThrowsError(
      try Envelope.open(combined: combined, contentKey: keyBad, aadCID: cid)
    )
  }
}
