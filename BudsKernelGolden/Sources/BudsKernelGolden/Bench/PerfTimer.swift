import Foundation

public struct PerfTimer {
  private let start = DispatchTime.now()

  public init() {}

  public func elapsedMs() -> Double {
    let end = DispatchTime.now()
    let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
    return Double(nanos) / 1_000_000.0
  }
}
