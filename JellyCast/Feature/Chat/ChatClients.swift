import Foundation

nonisolated struct ChatTurn: Sendable {
    enum Role: Sendable { case user, assistant }

    let role: Role
    let text: String
    /// The assistant's reply exactly as the service sent it, sent back unchanged on the next
    /// question (Claude's thinking blocks have to come back as they were).
    let providerContent: ChatJSON?
}

nonisolated struct ChatReply: Sendable {
    let text: String
    let providerContent: ChatJSON?
    var sources: [ChatSource] = []
}

/// A web page the answer is based on.
nonisolated struct ChatSource: Sendable, Hashable {
    let title: String
    let url: URL

    /// The first sources with a distinct address, in the order they were cited.
    static func unique(_ sources: [ChatSource], limit: Int = 5) -> [ChatSource] {
        var seen = Set<URL>()
        return Array(sources.filter { seen.insert($0.url).inserted }.prefix(limit))
    }

    /// "imdb.com": shorter and more recognisable than a page title.
    static func site(_ url: URL) -> String? {
        guard let host = url.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    init?(title: String?, url: String?) {
        guard let url = url.flatMap(URL.init(string:)) else { return nil }
        self.title = title ?? url.host() ?? url.absoluteString
        self.url = url
    }
}

nonisolated enum ChatError: Error, Equatable {
    case invalidKey
    case refused
    case rateLimited
    case unavailable(Int)
    case emptyReply

    var message: String {
        switch self {
        case .invalidKey: String(localized: "The API key isn't accepted. Check it under Settings → AI chat.")
        case .refused: String(localized: "The model won't answer this question.")
        case .rateLimited: String(localized: "Too many questions at once. Try again in a moment.")
        case .unavailable(let status): String(localized: "The service didn't answer (\(status)). Try again.")
        case .emptyReply: String(localized: "The answer was empty. Try again.")
        }
    }
}

/// What the model is doing while the answer is on its way.
nonisolated enum ChatProgress: Sendable {
    case searching(query: String)
    case found(sites: [String])
    case opening(site: String)
    case filtering
    /// The answer so far, replacing what came before.
    case answer(String)
}

/// Reports progress in order, on whatever actor the receiver needs.
typealias ChatProgressHandler = @Sendable (ChatProgress) async -> Void

nonisolated protocol ChatClient: Sendable {
    func reply(
        system: String, turns: [ChatTurn], searchesWeb: Bool, progress: @escaping ChatProgressHandler
    ) async throws -> ChatReply
    /// Checks that the key works, without a paid request where the service allows.
    func check() async throws
}
