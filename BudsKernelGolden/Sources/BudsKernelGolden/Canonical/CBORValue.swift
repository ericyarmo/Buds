import Foundation

public enum CBORValue {
  case int(Int64)
  case bool(Bool)
  case text(String)
  case bytes(Data)
  case array([CBORValue])
  case map([(CBORValue, CBORValue)]) // encoder will canonical-sort keys
}
