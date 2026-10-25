import Foundation

/// Any JSON value, so a reply can be kept and sent back exactly as it came.
nonisolated enum ChatJSON: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ChatJSON])
    case array([ChatJSON])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ChatJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ChatJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    subscript(key: String) -> ChatJSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    var numberValue: Double? { if case .number(let value) = self { value } else { nil } }
    var arrayValue: [ChatJSON]? { if case .array(let value) = self { value } else { nil } }
    var objectValue: [String: ChatJSON]? { if case .object(let value) = self { value } else { nil } }

    /// Sends the request and decodes the body, mapping the service's errors.
    static func load(_ request: URLRequest) async throws -> ChatJSON {
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        return try JSONDecoder().decode(ChatJSON.self, from: data)
    }

    /// Sends the request and hands over each server-sent event's data in order.
    static func stream(_ request: URLRequest, onEvent: (ChatJSON) async throws -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try check(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]", let event = try? JSONDecoder().decode(ChatJSON.self, from: Data(payload.utf8))
            else { continue }
            try await onEvent(event)
        }
    }

    private static func check(status: Int) throws {
        switch status {
        case 200..<300: return
        case 401, 403: throw ChatError.invalidKey
        case 429: throw ChatError.rateLimited
        default: throw ChatError.unavailable(status)
        }
    }
}
