import Foundation

/// The few protobuf messages of the Android TV remote protocol, written by hand: two message
/// types don't justify a code generator and a dependency.
nonisolated struct ProtoWriter: Sendable {
    private(set) var bytes: [UInt8] = []

    mutating func varint(_ field: Int, _ value: UInt64) {
        tag(field, wireType: 0)
        Self.appendVarint(value, to: &bytes)
    }

    mutating func bytes(_ field: Int, _ value: [UInt8]) {
        tag(field, wireType: 2)
        Self.appendVarint(UInt64(value.count), to: &bytes)
        bytes.append(contentsOf: value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Array(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.bytes)
    }

    /// The protocol sends every message after its length as a varint.
    var framed: [UInt8] {
        var framed: [UInt8] = []
        Self.appendVarint(UInt64(bytes.count), to: &framed)
        return framed + bytes
    }

    private mutating func tag(_ field: Int, wireType: UInt64) {
        Self.appendVarint(UInt64(field) << 3 | wireType, to: &bytes)
    }

    static func appendVarint(_ value: UInt64, to bytes: inout [UInt8]) {
        var value = value
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
    }
}

/// The fields of one message; unknown fields and wire types are skipped.
nonisolated struct ProtoMessage: Sendable {
    private var varints: [Int: UInt64] = [:]
    private var payloads: [Int: [UInt8]] = [:]

    init?(_ bytes: [UInt8]) {
        var index = 0
        while index < bytes.count {
            guard let key = Self.readVarint(bytes, &index) else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let value = Self.readVarint(bytes, &index) else { return nil }
                varints[field] = value
            case 2:
                guard let length = Self.readVarint(bytes, &index), index + Int(length) <= bytes.count else {
                    return nil
                }
                payloads[field] = Array(bytes[index..<index + Int(length)])
                index += Int(length)
            case 1: index += 8
            case 5: index += 4
            default: return nil
            }
        }
    }

    func has(_ field: Int) -> Bool { payloads[field] != nil || varints[field] != nil }

    func varint(_ field: Int) -> UInt64? { varints[field] }

    func message(_ field: Int) -> ProtoMessage? { payloads[field].flatMap(ProtoMessage.init) }

    static func readVarint(_ bytes: [UInt8], _ index: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 { return result }
            shift += 7
        }
        return nil
    }
}
