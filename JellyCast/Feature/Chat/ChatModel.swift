import Foundation
import Observation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatTurn.Role
    let text: String
    let providerContent: ChatJSON?
    var sources: [ChatSource] = []
    var searchCount = 0
}

/// One thing the model did on the way to an answer, shown while it works.
struct ChatStep: Identifiable, Equatable {
    enum Kind { case search, read, open, filter }

    let id = UUID()
    let kind: Kind
    let text: String
}

/// One conversation about a series or movie. It starts over when the series or movie changes.
@Observable
final class ChatModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isSending = false
    private(set) var error: ChatError?
    /// What the model did so far for the question it is answering.
    private(set) var steps: [ChatStep] = []
    /// The answer as far as it has arrived.
    private(set) var draft = ""
    private(set) var contextKey: String?

    @ObservationIgnored private var castByContext: [String: CastCredits] = [:]
    @ObservationIgnored private var sendTask: Task<Void, Never>?

    /// Keeps the conversation while the same series plays on; another series or movie starts over.
    func follow(_ playable: Playable) {
        let key = Self.contextKey(playable)
        guard key != contextKey else { return }
        reset()
        contextKey = key
    }

    func reset() {
        sendTask?.cancel()
        sendTask = nil
        messages = []
        isSending = false
        error = nil
        steps = []
        draft = ""
    }

    func send(_ text: String, about playable: Playable, store: LibraryStore) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending, let client = ChatSettings.shared.client() else { return }
        messages.append(ChatMessage(role: .user, text: question, providerContent: nil))
        ask(client, about: playable, store: store)
    }

    /// Asks again after an error, with the same question.
    func retry(about playable: Playable, store: LibraryStore) {
        guard !isSending, messages.last?.role == .user, let client = ChatSettings.shared.client() else { return }
        ask(client, about: playable, store: store)
    }

    private func ask(_ client: any ChatClient, about playable: Playable, store: LibraryStore) {
        isSending = true
        error = nil
        steps = []
        draft = ""
        let turns = messages.map { ChatTurn(role: $0.role, text: $0.text, providerContent: $0.providerContent) }
        sendTask = Task {
            do {
                let cast = await cast(for: playable, store: store)
                let settings = ChatSettings.shared
                let system = ChatContext.system(
                    for: playable, index: store.index, cast: cast,
                    avoidsSpoilers: settings.avoidsSpoilers, searchesWeb: settings.searchesWeb
                )
                let reply = try await client.reply(
                    system: system, turns: turns, searchesWeb: settings.searchesWeb
                ) { @MainActor progress in
                    self.show(progress)
                }
                guard !Task.isCancelled else { return }
                messages.append(ChatMessage(
                    role: .assistant, text: reply.text, providerContent: reply.providerContent,
                    sources: reply.sources, searchCount: steps.count { $0.kind == .search }
                ))
            } catch is CancellationError {
                return
            } catch let chatError as ChatError {
                error = chatError
            } catch {
                guard !Task.isCancelled else { return }
                self.error = .unavailable(0)
            }
            isSending = false
            steps = []
            draft = ""
        }
    }

    private func show(_ progress: ChatProgress) {
        switch progress {
        case .searching(let query):
            steps.append(ChatStep(kind: .search, text: String(localized: "Searching “\(query)”")))
            draft = ""
        case .found(let sites):
            steps.append(ChatStep(kind: .read, text: Self.foundText(sites)))
        case .opening(let site):
            steps.append(ChatStep(kind: .open, text: String(localized: "Reading \(site)")))
        case .filtering:
            guard steps.last?.kind != .filter else { return }
            steps.append(ChatStep(kind: .filter, text: String(localized: "Picking out what matters")))
        case .answer(let text):
            draft = text
        }
    }

    /// "8 results · imdb.com, wikipedia.org, variety.com and 5 more"
    private static func foundText(_ sites: [String]) -> String {
        var unique: [String] = []
        for site in sites where !unique.contains(site) { unique.append(site) }
        let shown = unique.prefix(Self.sitesShown).joined(separator: ", ")
        let more = unique.count - min(unique.count, Self.sitesShown)
        let list = more > 0 ? String(localized: "\(shown) and \(more) more") : shown
        return String(localized: "\(sites.count) results · \(list)")
    }

    private static let sitesShown = 3

    private func cast(for playable: Playable, store: LibraryStore) async -> CastCredits? {
        let key = playable.id
        if let cached = castByContext[key] { return cached }
        let loaded = try? await CastCredits.load(for: playable, session: store.session)
        if let loaded { castByContext[key] = loaded }
        return loaded
    }

    private static func contextKey(_ playable: Playable) -> String {
        switch playable {
        case .movie(let movie): movie.id
        case .episode(let episode): episode.seriesID
        }
    }
}

/// What the model is told about the series or movie, and how to answer.
nonisolated enum ChatContext {
    private static let maxCastNames = 25

    static func system(
        for playable: Playable, index: LibraryIndex?, cast: CastCredits?, avoidsSpoilers: Bool, searchesWeb: Bool
    ) -> String {
        var parts = [
            """
            You are the companion in JellyCast, a video app. The user is watching something and asks \
            quick questions about it. Answer in the language the user writes in, in a few sentences. \
            Markdown is shown formatted: use bold, lists, links and tables when they help, no headings \
            for a short answer. If you are not sure of a fact, say so rather than guess.
            """,
        ]
        switch playable {
        case .episode(let episode): parts += episodeContext(episode, index: index, avoidsSpoilers: avoidsSpoilers)
        case .movie(let movie): parts += movieContext(movie, avoidsSpoilers: avoidsSpoilers)
        }
        if let cast { parts.append(castContext(cast)) }
        if searchesWeb { parts.append(searchContext(avoidsSpoilers: avoidsSpoilers)) }
        return parts.joined(separator: "\n\n")
    }

    private static func episodeContext(_ episode: Episode, index: LibraryIndex?, avoidsSpoilers: Bool) -> [String] {
        let series = index?.seriesByID[episode.seriesID]
        let code = code(episode)
        var parts = [
            "The user is watching \(episode.seriesName)\(series?.year.map { " (\($0))" } ?? ""), "
                + "\(code) \"\(episode.name)\".",
        ]
        if avoidsSpoilers {
            parts.append("""
                The user has seen the series up to and including \(code). Never reveal anything that happens \
                after that episode: later episodes or seasons, who survives, twists or endings, even though you \
                may know them. If a question can't be answered without that, say so in one sentence.
                """)
        }
        if let overview = series?.overview { parts.append("About the series: \(overview)") }
        let episodes = (index?.progress(of: episode.seriesID)?.episodes ?? [])
            .filter { ($0.seasonNumber ?? 0) > 0 }
        let upToCurrent = episodes.prefix { $0.id != episode.id } + [episode]
        let list = upToCurrent.map { item in
            "\(self.code(item)) \"\(item.name)\"" + (item.overview.map { ": \($0)" } ?? "")
        }
        parts.append("Episodes up to the current one:\n" + list.joined(separator: "\n"))
        return parts
    }

    private static func movieContext(_ movie: Movie, avoidsSpoilers: Bool) -> [String] {
        var parts = [
            "The user is watching the movie \(movie.name)\(movie.year.map { " (\($0))" } ?? "").",
        ]
        if !movie.genres.isEmpty { parts.append("Genres: \(movie.genres.joined(separator: ", ")).") }
        if let overview = movie.overview { parts.append("Overview: \(overview)") }
        if avoidsSpoilers, !movie.watch.played {
            parts.append("""
                The user hasn't finished the movie. Don't reveal the ending, twists or who survives unless \
                the user explicitly asks for it.
                """)
        }
        return parts
    }

    private static func castContext(_ cast: CastCredits) -> String {
        let actors = (cast.actors + cast.guestStars).prefix(maxCastNames).map { credit in
            credit.role.map { "\(credit.name) as \($0)" } ?? credit.name
        }
        var lines = ["Cast: " + actors.joined(separator: "; ")]
        if !cast.directors.isEmpty { lines.append("Directed by: " + cast.directors.map(\.name).joined(separator: ", ")) }
        if !cast.writers.isEmpty { lines.append("Written by: " + cast.writers.map(\.name).joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    private static func searchContext(avoidsSpoilers: Bool) -> String {
        var text = """
            You can search the web. Search only when the answer depends on something this context and \
            your own knowledge don't cover well: real events behind the story, filming, reception, news \
            about the cast. Answer directly otherwise.
            """
        if avoidsSpoilers {
            text += """
                 Search results often summarize later episodes or the ending; leave out everything \
                that happens after what the user has seen, and prefer queries that won't return spoilers.
                """
        }
        return text
    }

    private static func code(_ episode: Episode) -> String {
        "S\(episode.seasonNumber ?? 0)E\(episode.episodeNumber ?? 0)"
    }
}
