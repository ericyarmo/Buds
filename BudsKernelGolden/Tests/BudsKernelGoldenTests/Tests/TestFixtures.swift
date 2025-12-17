//
//  TestFixtures.swift
//  BudsKernelGolden
//
//  Created by Eric Yarmolinsky on 12/16/25.
//


import Foundation

enum TestFixtures {
  /// Returns .../Tests/BudsKernelGoldenTests/Fixtures
  static func fixturesDir(file: StaticString = #filePath) -> URL {
    // file = .../Tests/BudsKernelGoldenTests/Tests/<ThisFile>.swift
    let testsDir = URL(fileURLWithPath: "\(file)")
      .deletingLastPathComponent()      // Tests/
      .deletingLastPathComponent()      // BudsKernelGoldenTests/
    return testsDir.appendingPathComponent("Fixtures", isDirectory: true)
  }

  static func url(name: String, ext: String, file: StaticString = #filePath) -> URL {
    fixturesDir(file: file).appendingPathComponent("\(name).\(ext)")
  }

  static func data(name: String, ext: String, file: StaticString = #filePath) throws -> Data {
    try Data(contentsOf: url(name: name, ext: ext, file: file))
  }

  static func string(name: String, ext: String, file: StaticString = #filePath) throws -> String {
    try String(contentsOf: url(name: name, ext: ext, file: file), encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
