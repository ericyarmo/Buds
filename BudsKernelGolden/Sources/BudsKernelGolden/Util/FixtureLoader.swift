import Foundation

public enum FixtureLoader {
  public static func url(in bundle: Bundle, name: String, ext: String) throws -> URL {
    guard let url = bundle.url(forResource: name, withExtension: ext) else {
      throw NSError(domain: "FixtureLoader", code: 404, userInfo: [
        NSLocalizedDescriptionKey: "Missing fixture: \(name).\(ext)"
      ])
    }
    return url
  }

  public static func data(in bundle: Bundle, name: String, ext: String) throws -> Data {
    let u = try url(in: bundle, name: name, ext: ext)
    return try Data(contentsOf: u)
  }

  public static func string(in bundle: Bundle, name: String, ext: String) throws -> String {
    let u = try url(in: bundle, name: name, ext: ext)
    return try String(contentsOf: u, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
