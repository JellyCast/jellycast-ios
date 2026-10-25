import Foundation

/// Claude through the Messages API with the user's own key, streamed so the searches show while
/// they run.
nonisolated struct ClaudeChatClient: ChatClient {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")
    private static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")
    private static let model = "claude-opus-5-5"
    private static let apiVersion = "2026-10-21"
    /// A declined question is retried on the model Anthropic recommends for that category.
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    private static let maxTokens = 16_000
    private static let timeout: TimeInterval = 120
    private static let maxSearches = 5
    /// A long search turn can pause; it is resumed by sending it back, a few times at most.
    private static let maxContinuations = 3

    func reply(
        system: String, turns: [ChatTurn], searchesWeb: Bool, progress: @escaping ChatProgressHandler
    ) async throws -> ChatReply {
        let messages: [ChatJSON] = turns.map { turn in
            switch turn.role {
            case .user: .object(["role": .string("user"), "content": .string(turn.text)])
            case .assistant:
                // Search blocks can't be sent back once the search tool is no longer offered.
                .object([
                    "role": .string("assistant"),
                    "content": searchesWeb ? turn.providerContent ?? .string(turn.text) : .string(turn.text),
                ])
            }
        }
        var message = ClaudeStreamedMessage()
        for _ in 0...Self.maxContinuations {
            let paused: [ChatJSON] = message.blocks.isEmpty
                ? [] : [.object(["role": .string("assistant"), "content": .array(message.blocks)])]
            message.stopReason = nil
            let request = try request(system: system, messages: messages + paused, searchesWeb: searchesWeb)
            try await ChatJSON.stream(request) { event in
                if let update = try message.apply(event) { await progress(update) }
            }
            if message.stopReason == "refusal" { throw ChatError.refused }
            if message.stopReason != "pause_turn" { break }
        }
        let text = ClaudeStreamedMessage.answerText(message.blocks)
        guard !text.isEmpty else { throw ChatError.emptyReply }
        return ChatReply(
            text: text, providerContent: .array(message.blocks),
            sources: ClaudeStreamedMessage.sources(message.blocks)
        )
    }

    func check() async throws {
        _ = try await ChatJSON.load(try request(url: Self.modelsEndpoint))
    }

    private func request(system: String, messages: [ChatJSON], searchesWeb: Bool) throws -> URLRequest {
        var body: [String: ChatJSON] = [
            "model": .string(Self.model),
            "max_tokens": .number(Double(Self.maxTokens)),
            "fallbacks": .string("default"),
            "stream": .bool(true),
            "system": .array([.object([
                "type": .string("text"), "text": .string(system),
                "cache_control": .object(["type": .string("ephemeral")]),
            ])]),
            "messages": .array(messages),
        ]
        if searchesWeb {
            body["tools"] = .array([.object([
                "type": .string("web_search_20260209"), "name": .string("web_search"),
                "max_uses": .number(Double(Self.maxSearches)),
            ])])
        }
        var urlRequest = try request(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        urlRequest.httpBody = try JSONEncoder().encode(ChatJSON.object(body))
        return urlRequest
    }

    private func request(url: URL?) throws -> URLRequest {
        guard let url else { throw ChatError.unavailable(0) }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }
}

/// Rebuilds Claude's content blocks from the stream, so the turn can be sent back unchanged.
nonisolated struct ClaudeStreamedMessage {
    private(set) var blocks: [ChatJSON] = []
    var stopReason: String?
    private var partialInput: [Int: String] = [:]
    /// Blocks of earlier, paused requests come first; the stream's indexes count from its own start.
    private var offset = 0

    /// Applies one event and returns what changed for the user, if anything.
    mutating func apply(_ event: ChatJSON) throws -> ChatProgress? {
        switch event["type"]?.stringValue {
        case "message_start":
            offset = blocks.count
            partialInput = [:]
        case "content_block_start":
            guard let block = event["content_block"] else { return nil }
            blocks.append(block)
            return Self.progress(startOf: block)
        case "content_block_delta":
            guard let index = index(event), let delta = event["delta"] else { return nil }
            return applyDelta(delta, at: index)
        case "content_block_stop":
            guard let index = index(event) else { return nil }
            return finishInput(at: index)
        case "message_delta":
            stopReason = event["delta"]?["stop_reason"]?.stringValue ?? stopReason
        case "error":
            throw event["error"]?["type"]?.stringValue == "rate_limit_error"
                ? ChatError.rateLimited : ChatError.unavailable(0)
        default:
            break
        }
        return nil
    }

    private func index(_ event: ChatJSON) -> Int? {
        guard let value = event["index"]?.numberValue else { return nil }
        let index = offset + Int(value)
        return blocks.indices.contains(index) ? index : nil
    }

    private mutating func applyDelta(_ delta: ChatJSON, at index: Int) -> ChatProgress? {
        guard var block = blocks[index].objectValue else { return nil }
        switch delta["type"]?.stringValue {
        case "text_delta":
            block["text"] = .string((block["text"]?.stringValue ?? "") + (delta["text"]?.stringValue ?? ""))
        case "input_json_delta":
            partialInput[index, default: ""] += delta["partial_json"]?.stringValue ?? ""
            return nil
        case "citations_delta":
            guard let citation = delta["citation"] else { return nil }
            block["citations"] = .array((block["citations"]?.arrayValue ?? []) + [citation])
        case "thinking_delta":
            block["thinking"] = .string(
                (block["thinking"]?.stringValue ?? "") + (delta["thinking"]?.stringValue ?? "")
            )
        case "signature_delta":
            block["signature"] = delta["signature"]
        default:
            return nil
        }
        blocks[index] = .object(block)
        guard block["type"]?.stringValue == "text" else { return nil }
        return .answer(Self.answerText(blocks))
    }

    private mutating func finishInput(at index: Int) -> ChatProgress? {
        guard let json = partialInput.removeValue(forKey: index), var block = blocks[index].objectValue
        else { return nil }
        let input = json.isEmpty ? ChatJSON.object([:]) : try? JSONDecoder().decode(ChatJSON.self, from: Data(json.utf8))
        block["input"] = input ?? .object([:])
        blocks[index] = .object(block)
        guard block["type"]?.stringValue == "server_tool_use" else { return nil }
        switch block["name"]?.stringValue {
        case "web_search":
            return block["input"]?["query"]?.stringValue.map { .searching(query: $0) }
        case let name? where name.contains("code_execution"):
            return .filtering
        default:
            return nil
        }
    }

    private static func progress(startOf block: ChatJSON) -> ChatProgress? {
        guard block["type"]?.stringValue == "web_search_tool_result",
              let results = block["content"]?.arrayValue
        else { return nil }
        let sites = results.compactMap { $0["url"]?.stringValue.flatMap(URL.init(string:)).flatMap(ChatSource.site) }
        return sites.isEmpty ? nil : .found(sites: sites)
    }

    /// The text after the last search: what comes before it is Claude saying it will look something
    /// up. Cited text arrives split over several blocks, so they are joined without a separator.
    static func answerText(_ blocks: [ChatJSON]) -> String {
        let lastTool = blocks.lastIndex { $0["type"]?.stringValue != "text" }
        let answer = lastTool.map { Array(blocks[blocks.index(after: $0)...]) } ?? blocks
        return answer.compactMap { $0["text"]?.stringValue }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sources(_ blocks: [ChatJSON]) -> [ChatSource] {
        let cited = blocks.flatMap { block -> [ChatSource] in
            (block["citations"]?.arrayValue ?? []).compactMap {
                ChatSource(title: $0["title"]?.stringValue, url: $0["url"]?.stringValue)
            }
        }
        return ChatSource.unique(cited)
    }
}
