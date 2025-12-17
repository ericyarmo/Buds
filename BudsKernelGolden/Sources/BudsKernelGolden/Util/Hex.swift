//
//  Hex.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//

import Foundation

public enum Hex {
  public static func encode(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
  }

  public static func decode(_ hex: String) -> Data? {
    let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.count % 2 == 0 else { return nil }
    var out = Data(capacity: s.count / 2)
    var idx = s.startIndex
    while idx < s.endIndex {
      let next = s.index(idx, offsetBy: 2)
      let byteStr = s[idx..<next]
      guard let b = UInt8(byteStr, radix: 16) else { return nil }
      out.append(b)
      idx = next
    }
    return out
  }
}
