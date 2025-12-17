//
//  ReceiptCanonicalizer.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation

public enum ReceiptCanonicalizer {
  public static func canonicalCBOR(_ receipt: UnsignedReceipt) throws -> Data {
    let enc = CBORCanonical()

    // payload map — omit nil fields by construction
    var payloadPairs: [(CBORValue, CBORValue)] = [
      (.text("claimed_time_ms"), .int(receipt.payload.claimed_time_ms))
    ]
    if let v = receipt.payload.product_name { payloadPairs.append((.text("product_name"), .text(v))) }
    if let v = receipt.payload.strain_type { payloadPairs.append((.text("strain_type"), .text(v))) }
    if let v = receipt.payload.notes { payloadPairs.append((.text("notes"), .text(v))) }
    if let v = receipt.payload.rating { payloadPairs.append((.text("rating"), .int(Int64(v)))) }

    let payload = CBORValue.map(payloadPairs)

    // outer receipt map — omit nil fields
    var pairs: [(CBORValue, CBORValue)] = [
      (.text("did"), .text(receipt.did)),
      (.text("deviceId"), .text(receipt.deviceId)),
      (.text("receiptType"), .text(receipt.receiptType)),
      (.text("payload"), payload),
    ]
    if let p = receipt.parentCID { pairs.append((.text("parentCID"), .text(p))) }
    if let r = receipt.rootCID { pairs.append((.text("rootCID"), .text(r))) }

    return try enc.encode(.map(pairs))
  }
}
