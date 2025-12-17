//
//  PerformanceTests.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import XCTest
@testable import BudsKernelGolden
import CryptoKit

final class PerformanceTests: XCTestCase {

  func testPerf_EncodeCIDSign_And_SealWrapOpen() throws {
    let jsonData = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let unsigned = try JSONDecoder().decode(UnsignedReceipt.self, from: jsonData)

    let authorSKRaw = Data(repeating: 0x11, count: 32)

    // Recipient device keypair
    let recipientSK = Curve25519.KeyAgreement.PrivateKey()
    let recipientPKRaw = recipientSK.publicKey.rawRepresentation

    // Warmup
    _ = try ReceiptCanonicalizer.canonicalCBOR(unsigned)

    let N = 200

    var timesA: [Double] = []
    var timesB: [Double] = []

    for _ in 0..<N {
      // A) canonicalize + CID + sign
      do {
        let t = PerfTimer()
        let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
        _ = CID.computeCIDv1DagCBORSha256(preimage)
        _ = try Signing.signEd25519(preimage: preimage, privateKeyRaw32: authorSKRaw)
        timesA.append(t.elapsedMs())
      }

      // B) seal + wrap + unwrap + open (includes AAD binding)
      do {
        let preimage = try ReceiptCanonicalizer.canonicalCBOR(unsigned)
        let cid = CID.computeCIDv1DagCBORSha256(preimage)

        let t = PerfTimer()
        let contentKey = SymmetricKey(size: .bits256)
        let combined = try Envelope.seal(plaintext: preimage, contentKey: contentKey, aadCID: cid)

        let contentKeyRaw = contentKey.withUnsafeBytes { Data($0) }
        let (ephPub, wrapped) = try KeyWrap.wrapContentKeyForRecipient(
          contentKeyRaw32: contentKeyRaw,
          recipientPublicKeyRaw32: recipientPKRaw
        )

        let unwrappedRaw = try KeyWrap.unwrapContentKeyForRecipient(
          ephemeralPublicKeyRaw32: ephPub,
          wrappedCombined: wrapped,
          recipientPrivateKey: recipientSK
        )

        let opened = try Envelope.open(combined: combined, contentKey: SymmetricKey(data: unwrappedRaw), aadCID: cid)
        XCTAssertEqual(opened, preimage)

        timesB.append(t.elapsedMs())
      }
    }

    func stats(_ xs: [Double]) -> (p50: Double, p95: Double) {
      let s = xs.sorted()
      func pct(_ p: Double) -> Double {
        let i = min(max(Int(Double(s.count - 1) * p), 0), s.count - 1)
        return s[i]
      }
      return (pct(0.50), pct(0.95))
    }

    let a = stats(timesA)
    let b = stats(timesB)

    print("Perf A (encode+cid+sign) p50=\(a.p50)ms p95=\(a.p95)ms")
    print("Perf B (seal+wrap+unwrap+open) p50=\(b.p50)ms p95=\(b.p95)ms")

    // Loose sanity thresholds just to catch regressions (we can tighten later)
    XCTAssertLessThan(a.p95, 50.0)
    XCTAssertLessThan(b.p95, 100.0)
  }
}
