//
//  Signing.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation
import CryptoKit

public enum Signing {
  public static func signEd25519(preimage: Data, privateKeyRaw32: Data) throws -> Data {
    let sk = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw32)
    return try sk.signature(for: preimage)
  }

  public static func verifyEd25519(preimage: Data, signature: Data, publicKeyRaw32: Data) -> Bool {
    do {
      let pk = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyRaw32)
      return pk.isValidSignature(signature, for: preimage)
    } catch {
      return false
    }
  }
}
