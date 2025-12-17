//
//  CBORCanonical.swift
//  Buds
//
//  Canonical CBOR encoder (RFC 8949)
//  Ported from BudsKernelGolden (physics-tested: 0.11ms p50)
//

import Foundation

struct CBORCanonical {
    init() {}

    func encode(_ value: CBORValue) throws -> Data {
        var out = Data()
        try encodeInto(&out, value)
        return out
    }

    private func encodeInto(_ out: inout Data, _ v: CBORValue) throws {
        switch v {
        case .int(let i):
            encodeInt(&out, i)
        case .bool(let b):
            out.append(b ? 0xF5 : 0xF4)
        case .text(let s):
            encodeText(&out, s)
        case .bytes(let d):
            encodeBytes(&out, d)
        case .array(let arr):
            try encodeArray(&out, arr)
        case .map(let pairs):
            try encodeMap(&out, pairs)
        }
    }

    private func encodeUInt(_ out: inout Data, major: UInt8, value: UInt64) {
        func head(_ addl: UInt8) { out.append((major << 5) | addl) }

        switch value {
        case 0...23:
            head(UInt8(value))
        case 24...0xFF:
            head(24); out.append(UInt8(value))
        case 0x100...0xFFFF:
            head(25)
            out.append(UInt8((value >> 8) & 0xFF))
            out.append(UInt8(value & 0xFF))
        case 0x1_0000...0xFFFF_FFFF:
            head(26)
            for shift in stride(from: 24, through: 0, by: -8) {
                out.append(UInt8((value >> UInt64(shift)) & 0xFF))
            }
        default:
            head(27)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((value >> UInt64(shift)) & 0xFF))
            }
        }
    }

    private func encodeInt(_ out: inout Data, _ i: Int64) {
        if i >= 0 {
            encodeUInt(&out, major: 0, value: UInt64(i))
        } else {
            // CBOR negative int encodes (-1 - n)
            let n = UInt64(-1 - i)
            encodeUInt(&out, major: 1, value: n)
        }
    }

    private func encodeText(_ out: inout Data, _ s: String) {
        let b = Data(s.utf8)
        encodeUInt(&out, major: 3, value: UInt64(b.count))
        out.append(b)
    }

    private func encodeBytes(_ out: inout Data, _ d: Data) {
        encodeUInt(&out, major: 2, value: UInt64(d.count))
        out.append(d)
    }

    private func encodeArray(_ out: inout Data, _ arr: [CBORValue]) throws {
        encodeUInt(&out, major: 4, value: UInt64(arr.count))
        for x in arr { try encodeInto(&out, x) }
    }

    private func encodeMap(_ out: inout Data, _ pairs: [(CBORValue, CBORValue)]) throws {
        // Canonical map: sort by CBOR-encoded key bytes (lexicographic)
        let enc = CBORCanonical()
        let decorated = try pairs.map { (k, v) -> (Data, CBORValue, CBORValue) in
            (try enc.encode(k), k, v)
        }.sorted { a, b in
            a.0.lexicographicallyPrecedes(b.0)
        }

        encodeUInt(&out, major: 5, value: UInt64(decorated.count))
        for (_, k, v) in decorated {
            try encodeInto(&out, k)
            try encodeInto(&out, v)
        }
    }
}
