//
//  CBORDecoder.swift
//  Buds
//
//  Canonical CBOR decoder (RFC 8949)
//  Decodes CBOR bytes back to CBORValue for receipt verification
//

import Foundation

struct CBORDecoder {

    /// Decode CBOR data to CBORValue
    func decode(_ data: Data) throws -> CBORValue {
        var offset = 0
        return try decodeValue(data, offset: &offset)
    }

    // MARK: - Private Decoding

    private func decodeValue(_ data: Data, offset: inout Int) throws -> CBORValue {
        guard offset < data.count else {
            throw CBORDecodeError.unexpectedEnd
        }

        let byte = data[offset]
        offset += 1

        let majorType = byte >> 5
        let additional = byte & 0x1F

        switch majorType {
        case 0: // Unsigned integer
            let value = try readUInt(data, offset: &offset, additional: additional)
            return .int(Int64(value))

        case 1: // Negative integer
            let value = try readUInt(data, offset: &offset, additional: additional)
            // CBOR negative int: -1 - n
            return .int(-1 - Int64(value))

        case 2: // Byte string
            let bytes = try readBytes(data, offset: &offset, additional: additional)
            return .bytes(bytes)

        case 3: // Text string
            let text = try readText(data, offset: &offset, additional: additional)
            return .text(text)

        case 4: // Array
            return try readArray(data, offset: &offset, additional: additional)

        case 5: // Map
            return try readMap(data, offset: &offset, additional: additional)

        case 7: // Simple values / floats / booleans
            if additional == 20 {
                return .bool(false)
            } else if additional == 21 {
                return .bool(true)
            } else {
                throw CBORDecodeError.unsupportedType
            }

        default:
            throw CBORDecodeError.unsupportedType
        }
    }

    // MARK: - Read Helpers

    private func readUInt(_ data: Data, offset: inout Int, additional: UInt8) throws -> UInt64 {
        switch additional {
        case 0...23:
            return UInt64(additional)

        case 24: // 1-byte uint
            guard offset < data.count else { throw CBORDecodeError.unexpectedEnd }
            let value = UInt64(data[offset])
            offset += 1
            return value

        case 25: // 2-byte uint
            guard offset + 1 < data.count else { throw CBORDecodeError.unexpectedEnd }
            let value = UInt64(data[offset]) << 8 | UInt64(data[offset + 1])
            offset += 2
            return value

        case 26: // 4-byte uint
            guard offset + 3 < data.count else { throw CBORDecodeError.unexpectedEnd }
            var value: UInt64 = 0
            for i in 0..<4 {
                value = (value << 8) | UInt64(data[offset + i])
            }
            offset += 4
            return value

        case 27: // 8-byte uint
            guard offset + 7 < data.count else { throw CBORDecodeError.unexpectedEnd }
            var value: UInt64 = 0
            for i in 0..<8 {
                value = (value << 8) | UInt64(data[offset + i])
            }
            offset += 8
            return value

        default:
            throw CBORDecodeError.invalidAdditional
        }
    }

    private func readBytes(_ data: Data, offset: inout Int, additional: UInt8) throws -> Data {
        let length = try readUInt(data, offset: &offset, additional: additional)
        guard offset + Int(length) <= data.count else {
            throw CBORDecodeError.unexpectedEnd
        }

        let bytes = data.subdata(in: offset..<(offset + Int(length)))
        offset += Int(length)
        return bytes
    }

    private func readText(_ data: Data, offset: inout Int, additional: UInt8) throws -> String {
        let bytes = try readBytes(data, offset: &offset, additional: additional)
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw CBORDecodeError.invalidUTF8
        }
        return text
    }

    private func readArray(_ data: Data, offset: inout Int, additional: UInt8) throws -> CBORValue {
        let length = try readUInt(data, offset: &offset, additional: additional)
        var items: [CBORValue] = []

        for _ in 0..<length {
            let value = try decodeValue(data, offset: &offset)
            items.append(value)
        }

        return .array(items)
    }

    private func readMap(_ data: Data, offset: inout Int, additional: UInt8) throws -> CBORValue {
        let length = try readUInt(data, offset: &offset, additional: additional)
        var pairs: [(CBORValue, CBORValue)] = []

        for _ in 0..<length {
            let key = try decodeValue(data, offset: &offset)
            let value = try decodeValue(data, offset: &offset)
            pairs.append((key, value))
        }

        return .map(pairs)
    }
}

// MARK: - Errors

enum CBORDecodeError: Error, LocalizedError {
    case unexpectedEnd
    case unsupportedType
    case invalidUTF8
    case invalidStructure
    case invalidAdditional
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedEnd:
            return "Unexpected end of CBOR data"
        case .unsupportedType:
            return "Unsupported CBOR type"
        case .invalidUTF8:
            return "Invalid UTF-8 in CBOR text string"
        case .invalidStructure:
            return "Invalid CBOR structure"
        case .invalidAdditional:
            return "Invalid CBOR additional information"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}
