//
//  Base32.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//


import Foundation

public enum Base32 {
  private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")

  public static func encode(_ data: Data) -> String {
    var bits = 0
    var value: UInt32 = 0
    var out = ""

    for byte in data {
      value = (value << 8) | UInt32(byte)
      bits += 8
      while bits >= 5 {
        let idx = Int((value >> UInt32(bits - 5)) & 0x1F)
        out.append(alphabet[idx])
        bits -= 5
      }
    }

    if bits > 0 {
      let idx = Int((value << UInt32(5 - bits)) & 0x1F)
      out.append(alphabet[idx])
    }

    return out
  }
}

