//
//  SessionPayload.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation

public struct SessionPayload: Codable, Equatable {
  public let claimed_time_ms: Int64
  public let product_name: String?
  public let strain_type: String?
  public let notes: String?
  public let rating: Int?

  public init(
    claimed_time_ms: Int64,
    product_name: String?,
    strain_type: String?,
    notes: String?,
    rating: Int?
  ) {
    self.claimed_time_ms = claimed_time_ms
    self.product_name = product_name
    self.strain_type = strain_type
    self.notes = notes
    self.rating = rating
  }
}
