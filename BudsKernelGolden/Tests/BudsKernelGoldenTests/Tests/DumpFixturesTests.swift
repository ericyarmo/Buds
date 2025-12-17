import XCTest

final class DumpFixturesTests: XCTestCase {

  func testDumpVector1UnsignedJsonBytes() throws {
    let data = try TestFixtures.data(name: "vector1_unsigned", ext: "json")
    let url = TestFixtures.url(name: "vector1_unsigned", ext: "json")

    print("Fixture url:", url.path)
    print("Fixture byteCount:", data.count)
    print("Fixture preview:", String(data: data, encoding: .utf8) ?? "<not utf8>")

    XCTAssertGreaterThan(data.count, 5, "Fixture is empty/truncated on disk")
  }
}
