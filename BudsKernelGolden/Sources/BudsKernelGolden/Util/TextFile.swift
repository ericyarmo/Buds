//
//  TextFile.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//


import Foundation

public enum TextFile {
  public static func readString(from url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
