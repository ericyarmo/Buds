//
//  Envelope.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation
import CryptoKit

public enum Envelope {

  /// Encrypt raw receipt CBOR bytes using AES-GCM. AAD is receipt CID (utf8).
  public static func seal(
    plaintext: Data,
    contentKey: SymmetricKey,
    aadCID: String
  ) throws -> Data {
    let aad = Data(aadCID.utf8)
    let sealed = try AES.GCM.seal(plaintext, using: contentKey, authenticating: aad)
    guard let combined = sealed.combined else {
      throw NSError(domain: "Envelope", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing combined box"])
    }
    return combined
  }

  /// Decrypt AES-GCM combined using the same AAD CID.
  public static func open(
    combined: Data,
    contentKey: SymmetricKey,
    aadCID: String
  ) throws -> Data {
    let aad = Data(aadCID.utf8)
    let box = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(box, using: contentKey, authenticating: aad)
  }
}
