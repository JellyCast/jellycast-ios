import SwiftUI

/// Questions about what plays, answered by the AI service the user set a key for.
struct ChatTab: View {
    let playable: Playable
    let store: LibraryStore
    let model: ChatModel

    private var suggestions: [String] {
        let whoIsWho = String(localized: "Who is who?")
        let real = String(localized: "Is this based on real events?")
        switch playable {
        case .episode: return [String(localized: "What happened in the previous episode?"), whoIsWho, real]
        case .movie: return [whoIsWho, real, String(localized: "What should I know before watching?")]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            contextRow
            if model.messages.isEmpty {
                suggestionChips
            } else {
                ForEach(model.messages) { message in
                    ChatBubble(message: message)
                }
            }
            if model.isSending {
                ChatWorking(steps: model.steps, draft: model.draft)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.message).font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
                    Button("Try again") { model.retry(about: playable, store: store) }
                        .buttonStyle(.glass)
                }
            }
            if !model.messages.isEmpty {
                Text(sourceNote)
                    .font(.caption)
                    .foregroundStyle(JellyCastColors.textMuted)
            }
        }
        .onChange(of: playable.id, initial: true) { model.follow(playable) }
    }

    private var contextRow: some View {
        HStack(spacing: 8) {
            Image(systemName: ChatSettings.shared.avoidsSpoilers ? "eye.slash" : "eye")
                .font(.footnote)
                .foregroundStyle(JellyCastColors.textMuted)
            Text(contextTitle)
                .font(.footnote)
                .foregroundStyle(JellyCastColors.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !model.messages.isEmpty {
                Button { model.reset() } label: {
                    Label("New conversation", systemImage: "arrow.counterclockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(JellyCastColors.text)
                }
                .buttonStyle(PressedOpacityButtonStyle())
            }
        }
    }

    private var contextTitle: String {
        guard ChatSettings.shared.avoidsSpoilers else { return String(localized: "Spoilers allowed") }
        switch playable {
        case .episode(let episode):
            return String(localized: "No spoilers after \(Format.seasonEpisode(episode))")
        case .movie:
            return String(localized: "No spoilers")
        }
    }

    private var sourceNote: String {
        String(localized: "Answers by \(ChatSettings.shared.provider.title), with the series or movie info from your server. Can be wrong.")
    }

    private var suggestionChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    model.send(suggestion, about: playable, store: store)
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(JellyCastColors.surface, in: .capsule)
                }
                .buttonStyle(PressedOpacityButtonStyle())
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(JellyCastColors.rail, in: .rect(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 40)
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                MarkdownText(message.text)
                    .textSelection(.enabled)
                if message.searchCount > 0 {
                    Label(Self.searchedText(message.searchCount), systemImage: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(JellyCastColors.textMuted)
                }
                if !message.sources.isEmpty { ChatSources(sources: message.sources) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ChatBubble {
    fileprivate static func searchedText(_ count: Int) -> String {
        count == 1 ? String(localized: "Searched the web once") : String(localized: "Searched the web \(count) times")
    }
}

/// While the answer is on its way: each search and site, then the answer as it is written.
private struct ChatWorking: View {
    let steps: [ChatStep]
    let draft: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { step in
                row(step.text, systemImage: Self.icon(step.kind), isCurrent: step == steps.last && draft.isEmpty)
            }
            if draft.isEmpty {
                if steps.isEmpty { row(String(localized: "Thinking…"), systemImage: "sparkle", isCurrent: true) }
            } else {
                MarkdownText(draft)
            }
        }
        .animation(.easeOut(duration: 0.2), value: steps.count)
    }

    private func row(_ text: String, systemImage: String, isCurrent: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if isCurrent {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: systemImage).font(.caption)
                }
            }
            .frame(width: 16)
            Text(text).font(.footnote).lineLimit(2)
        }
        .foregroundStyle(JellyCastColors.textMuted)
        .transition(.opacity)
    }

    private static func icon(_ kind: ChatStep.Kind) -> String {
        switch kind {
        case .search: "magnifyingglass"
        case .read: "globe"
        case .open: "doc.text"
        case .filter: "line.3.horizontal.decrease"
        }
    }
}

/// The web pages an answer is based on, as small links.
private struct ChatSources: View {
    let sources: [ChatSource]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(sources, id: \.url) { source in
                Link(destination: source.url) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe").font(.caption2)
                        Text(verbatim: Self.label(source)).font(.caption).lineLimit(1)
                    }
                    .foregroundStyle(JellyCastColors.textMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(JellyCastColors.surface, in: .capsule)
                }
                .buttonStyle(PressedOpacityButtonStyle())
                .accessibilityLabel(Text(verbatim: source.title))
            }
        }
    }

    private static func label(_ source: ChatSource) -> String {
        ChatSource.site(source.url) ?? source.title
    }
}

/// The question field, pinned under the conversation.
struct ChatInputBar: View {
    let title: String
    let isSending: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: (String) -> Void

    @State private var text = ""

    private static let sendSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 10) {
            TextField("Ask something about \(title)…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.text)
                .focused(isFocused)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(JellyCastColors.onAccent)
                    .frame(width: Self.sendSize, height: Self.sendSize)
                    .background(JellyCastColors.accent, in: .circle)
            }
            .buttonStyle(PressedOpacityButtonStyle())
            .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(JellyCastColors.surface, in: .rect(cornerRadius: 22))
    }

    private func send() {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isSending else { return }
        onSend(question)
        text = ""
    }
}

/// Lays chips out in rows, wrapping to the next row when one doesn't fit.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([index], size.width, size.height)
            } else {
                current = (current.indices + [index], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
