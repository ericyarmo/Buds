//
//  WrappedKey.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//


import Foundation

public struct WrappedKey: Codable, Equatable {
  /// Recipient device identifier (string you control)
  public let device_id: String

  /// Recipient public key rawRepresentation (32 bytes) – optional but nice for debugging
  public let recipient_pubkey: Data

  /// AES-GCM combined: nonce || ciphertext || tag
  public let wrapped_key: Data

  public init(device_id: String, recipient_pubkey: Data, wrapped_key: Data) {
    self.device_id = device_id
    self.recipient_pubkey = recipient_pubkey
    self.wrapped_key = wrapped_key
  }
}
