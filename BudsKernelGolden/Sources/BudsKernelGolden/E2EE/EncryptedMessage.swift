//
//  EncryptedMessage.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation

public struct EncryptedMessage: Codable, Equatable {
  /// CID of the plaintext receipt (used as AAD)
  public let receipt_cid: String

  /// AES-GCM combined: nonce || ciphertext || tag
  public let encrypted_payload: Data

  public init(receipt_cid: String, encrypted_payload: Data) {
    self.receipt_cid = receipt_cid
    self.encrypted_payload = encrypted_payload
  }
}
