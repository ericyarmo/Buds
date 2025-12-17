//
//  UnsignedReceipt.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation

public struct UnsignedReceipt: Codable, Equatable {
  public let did: String
  public let deviceId: String
  public let parentCID: String?
  public let rootCID: String?
  public let receiptType: String
  public let payload: SessionPayload

  public init(
    did: String,
    deviceId: String,
    parentCID: String?,
    rootCID: String?,
    receiptType: String,
    payload: SessionPayload
  ) {
    self.did = did
    self.deviceId = deviceId
    self.parentCID = parentCID
    self.rootCID = rootCID
    self.receiptType = receiptType
    self.payload = payload
  }
}
