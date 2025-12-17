//
//  Keywrap.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation
import CryptoKit

public enum KeyWrap {

  /// Wrap a content key for a recipient device using X25519 + HKDF + AES-GCM.
  /// Returns (ephemeralPublicKeyRaw32, wrappedKeyCombined).
  public static func wrapContentKeyForRecipient(
    contentKeyRaw32: Data,
    recipientPublicKeyRaw32: Data,
    aad: Data = Data("wrap".utf8)
  ) throws -> (ephemeralPublicKeyRaw32: Data, wrappedCombined: Data) {

    let eph = Curve25519.KeyAgreement.PrivateKey()
    let ephPub = eph.publicKey.rawRepresentation

    let recipientPK = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyRaw32)
    let shared = try eph.sharedSecretFromKeyAgreement(with: recipientPK)

    // Derive a symmetric wrapping key
    let wrapKey = shared.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: Data("buds.keywrap.salt".utf8),
      sharedInfo: Data("buds.keywrap.info".utf8),
      outputByteCount: 32
    )

    let sealed = try AES.GCM.seal(contentKeyRaw32, using: wrapKey, authenticating: aad)
    guard let combined = sealed.combined else {
      throw NSError(domain: "KeyWrap", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing combined box"])
    }

    return (ephPub, combined)
  }

  /// Unwrap a wrapped content key using recipient private key and sender ephemeral pubkey.
  public static func unwrapContentKeyForRecipient(
    ephemeralPublicKeyRaw32: Data,
    wrappedCombined: Data,
    recipientPrivateKey: Curve25519.KeyAgreement.PrivateKey,
    aad: Data = Data("wrap".utf8)
  ) throws -> Data {

    let ephPK = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPublicKeyRaw32)
    let shared = try recipientPrivateKey.sharedSecretFromKeyAgreement(with: ephPK)

    let wrapKey = shared.hkdfDerivedSymmetricKey(
      using: SHA256.self,
      salt: Data("buds.keywrap.salt".utf8),
      sharedInfo: Data("buds.keywrap.info".utf8),
      outputByteCount: 32
    )

    let box = try AES.GCM.SealedBox(combined: wrappedCombined)
    return try AES.GCM.open(box, using: wrapKey, authenticating: aad)
  }
}

