//
//  KeyWrapTests.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//


import XCTest
@testable import BudsKernelGolden
import CryptoKit

final class KeyWrapTests: XCTestCase {

  func testWrapUnwrap_RoundTrip() throws {
    // Content key to wrap (32 bytes)
    let contentKeyRaw32 = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

    // Recipient device keypair
    let recipientSK = Curve25519.KeyAgreement.PrivateKey()
    let recipientPKRaw = recipientSK.publicKey.rawRepresentation

    let (ephPub, wrapped) = try KeyWrap.wrapContentKeyForRecipient(
      contentKeyRaw32: contentKeyRaw32,
      recipientPublicKeyRaw32: recipientPKRaw
    )

    let unwrapped = try KeyWrap.unwrapContentKeyForRecipient(
      ephemeralPublicKeyRaw32: ephPub,
      wrappedCombined: wrapped,
      recipientPrivateKey: recipientSK
    )

    XCTAssertEqual(unwrapped, contentKeyRaw32)
  }

  func testUnwrap_Fails_ForWrongRecipient() throws {
    let contentKeyRaw32 = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

    let recipientA = Curve25519.KeyAgreement.PrivateKey()
    let recipientB = Curve25519.KeyAgreement.PrivateKey()

    let (ephPub, wrapped) = try KeyWrap.wrapContentKeyForRecipient(
      contentKeyRaw32: contentKeyRaw32,
      recipientPublicKeyRaw32: recipientA.publicKey.rawRepresentation
    )

    XCTAssertThrowsError(
      try KeyWrap.unwrapContentKeyForRecipient(
        ephemeralPublicKeyRaw32: ephPub,
        wrappedCombined: wrapped,
        recipientPrivateKey: recipientB
      )
    )
  }
}
