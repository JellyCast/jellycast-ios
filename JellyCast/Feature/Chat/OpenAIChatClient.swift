import Foundation

/// ChatGPT through the Responses API with the user's own key, streamed so the searches show while
/// they run. Chat Completions only searches the web with separate search models.
nonisolated struct OpenAIChatClient: ChatClient {
    let apiKey: String

    private static let endpoint = URL(string: "https://api.openai.com/v1/responses")
    private static let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")
    private static let preferredModel = "gpt-5.5"
    private static let modelKey = "openAIChatModel"
    private static let timeout: TimeInterval = 120
    /// Variants that aren't the general chat model.
    private static let excludedModelWords = [
        "mini", "nano", "audio", "realtime", "image", "search", "transcribe", "tts", "codex", "instruct", "oss",
    ]

    func reply(
        system: String, turns: [ChatTurn], searchesWeb: Bool, progress: @escaping ChatProgressHandler
    ) async throws -> ChatReply {
        let request = { (model: String) in
            try self.request(system: system, turns: turns, searchesWeb: searchesWeb, model: model)
        }
        do {
            return try await stream(request(Self.storedModel ?? Self.preferredModel), progress: progress)
        } catch ChatError.unavailable(404) {
            return try await stream(request(try await resolveModel()), progress: progress)
        }
    }

    func check() async throws {
        _ = try await resolveModel()
    }

    private func stream(_ request: URLRequest, progress: ChatProgressHandler) async throws -> ChatReply {
        var text = ""
        var completed: ChatJSON?
        try await ChatJSON.stream(request) { event in
            switch event["type"]?.stringValue {
            case "response.output_text.delta":
                text += event["delta"]?.stringValue ?? ""
                await progress(.answer(text))
            case "response.output_item.done":
                if let update = event["item"].flatMap(Self.progress) { await progress(update) }
            case "response.completed", "response.incomplete":
                completed = event["response"]
            case "response.failed", "error":
                throw ChatError.unavailable(0)
            default:
                break
            }
        }
        guard let completed else { throw ChatError.emptyReply }
        return try Self.reply(from: completed)
    }

    private static func progress(_ item: ChatJSON) -> ChatProgress? {
        guard item["type"]?.stringValue == "web_search_call", let action = item["action"] else { return nil }
        switch action["type"]?.stringValue {
        case "search":
            let query = action["query"]?.stringValue ?? action["queries"]?.arrayValue?.first?.stringValue
            return query.map { .searching(query: $0) }
        case "open_page", "find_in_page":
            return action["url"]?.stringValue.flatMap(URL.init(string:)).flatMap(ChatSource.site)
                .map { .opening(site: $0) }
        default:
            return nil
        }
    }

    private static func reply(from response: ChatJSON) throws -> ChatReply {
        let content = (response["output"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "message" }
            .flatMap { $0["content"]?.arrayValue ?? [] }
        let parts = content.filter { $0["type"]?.stringValue == "output_text" }
        if parts.isEmpty, content.contains(where: { $0["type"]?.stringValue == "refusal" }) {
            throw ChatError.refused
        }
        let text = parts.compactMap { $0["text"]?.stringValue }.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChatError.emptyReply }
        let cited = parts.flatMap { part -> [ChatSource] in
            (part["annotations"]?.arrayValue ?? []).filter { $0["type"]?.stringValue == "url_citation" }
                .compactMap { ChatSource(title: $0["title"]?.stringValue, url: $0["url"]?.stringValue) }
        }
        return ChatReply(text: text, providerContent: nil, sources: ChatSource.unique(cited))
    }

    private func request(system: String, turns: [ChatTurn], searchesWeb: Bool, model: String) throws -> URLRequest {
        let input: [ChatJSON] = turns.map { turn in
            .object(["role": .string(turn.role == .user ? "user" : "assistant"), "content": .string(turn.text)])
        }
        var body: [String: ChatJSON] = [
            "model": .string(model),
            "instructions": .string(system),
            "input": .array(input),
            "store": .bool(false),
            "stream": .bool(true),
        ]
        if searchesWeb { body["tools"] = .array([.object(["type": .string("web_search")])]) }
        var urlRequest = try request(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(ChatJSON.object(body))
        return urlRequest
    }

    /// The model names change often, so the newest general model is read from the key's list.
    private func resolveModel() async throws -> String {
        let response = try await ChatJSON.load(try request(url: Self.modelsEndpoint))
        let candidates = (response["data"]?.arrayValue ?? []).compactMap { model -> (id: String, created: Double)? in
            guard let id = model["id"]?.stringValue, id.hasPrefix("gpt-"),
                  !Self.excludedModelWords.contains(where: id.contains)
            else { return nil }
            return (id, model["created"]?.numberValue ?? 0)
        }
        let chosen = candidates.first { $0.id == Self.preferredModel }?.id
            ?? candidates.max { $0.created < $1.created }?.id
        guard let chosen else { throw ChatError.unavailable(404) }
        UserDefaults.standard.set(chosen, forKey: Self.modelKey)
        return chosen
    }

    private static var storedModel: String? { UserDefaults.standard.string(forKey: modelKey) }

    private func request(url: URL?) throws -> URLRequest {
        guard let url else { throw ChatError.unavailable(0) }
        var request = URLRequest(url: url, timeoutInterval: Self.timeout)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }
}
