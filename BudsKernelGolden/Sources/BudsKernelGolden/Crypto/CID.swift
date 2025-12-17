//
//  CID.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation
import CryptoKit

public enum CID {
  /// CIDv1 + dag-cbor + sha2-256 multihash, encoded as lowercase base32 with 'b' prefix.
  public static func computeCIDv1DagCBORSha256(_ preimage: Data) -> String {
    let hash = SHA256.hash(data: preimage)
    let hashBytes = Data(hash)

    var multihash = Data()
    multihash.append(0x12) // sha2-256
    multihash.append(0x20) // 32 bytes
    multihash.append(hashBytes)

    var cid = Data()
    cid.append(0x01) // CIDv1
    cid.append(0x71) // dag-cbor
    cid.append(multihash)

    return "b" + Base32.encode(cid).lowercased()
  }
}
