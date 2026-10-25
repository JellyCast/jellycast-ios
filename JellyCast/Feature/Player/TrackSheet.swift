import AetherEngine
import SwiftUI

struct TrackChoice: Identifiable, Equatable {
    let id: Int
    let title: String
    var detail: String?
}

/// Audio and subtitles behind one button, the same in the player and for a TV. It stays open
/// after a choice, so both can be set in one go.
struct TrackSheet: View {
    let audio: [TrackChoice]
    let selectedAudio: Int?
    let subtitles: [TrackChoice]
    /// `nil` is off.
    let selectedSubtitle: Int?
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(title: String(localized: "Audio and subtitles"))
                section("Audio")
                ForEach(audio) { choice in
                    CheckedSheetRow(title: choice.title, detail: choice.detail, isChecked: choice.id == selectedAudio) {
                        if choice.id != selectedAudio { onSelectAudio(choice.id) }
                    }
                }
                section("Subtitles").padding(.top, 8)
                CheckedSheetRow(title: String(localized: "Off"), isChecked: selectedSubtitle == nil) {
                    if selectedSubtitle != nil { onSelectSubtitle(nil) }
                }
                ForEach(subtitles) { choice in
                    CheckedSheetRow(
                        title: choice.title, detail: choice.detail, isChecked: choice.id == selectedSubtitle
                    ) {
                        if choice.id != selectedSubtitle { onSelectSubtitle(choice.id) }
                    }
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(JellyCastColors.textMuted)
            .padding(.horizontal, 4)
    }
}

extension TrackSheet {
    /// The streams as the server knows them, for a transcode and for a TV.
    static func choices(_ streams: [MediaInfo.Stream]) -> [TrackChoice] {
        streams.compactMap { stream in
            stream.Index.map { TrackChoice(id: $0, title: stream.DisplayTitle ?? stream.Codec ?? "") }
        }
    }

    static func subtitleChoices(_ streams: [MediaInfo.Stream]) -> [TrackChoice] {
        subtitleChoices(streams.compactMap { stream in
            stream.Index.map {
                SubtitleOrder.Track(
                    id: $0, language: stream.Language, title: stream.Title, codec: stream.Codec,
                    isHearingImpaired: stream.IsHearingImpaired ?? false, isForced: stream.IsForced ?? false
                )
            }
        })
    }

    static func subtitleChoices(_ tracks: [SubtitleOrder.Track]) -> [TrackChoice] {
        SubtitleOrder.entries(tracks, preferred: UserLanguages.shared.codes).enumerated().map { index, entry in
            let name = entry.language ?? entry.title ?? String(localized: "Track \(index + 1)")
            let details = [
                entry.language == nil ? nil : entry.title,
                entry.isSDH ? "SDH" : nil,
                entry.isForced ? String(localized: "Forced") : nil,
                entry.isImage ? String(localized: "Image") : nil,
            ].compactMap { $0 }
            return TrackChoice(
                id: entry.id,
                title: entry.number.map { "\(name) \($0)" } ?? name,
                detail: details.isEmpty ? nil : details.joined(separator: " · ")
            )
        }
    }
}

/// The player's own tracks, or the server's while it transcodes.
struct PlayerTrackSheet: View {
    @ObservedObject var engine: AetherEngine
    let session: PlayerSession

    var body: some View {
        if session.isTranscoding, let info = session.mediaInfo {
            TrackSheet(
                audio: TrackSheet.choices(info.audioStreams),
                selectedAudio: session.transcodeAudioIndex
                    ?? info.audioStreams.first { $0.IsDefault == true }?.Index
                    ?? info.audioStreams.first?.Index,
                subtitles: TrackSheet.subtitleChoices(info.subtitleStreams),
                selectedSubtitle: session.transcodeSubtitleIndex,
                onSelectAudio: { index in Task { await session.selectTranscodeAudio(streamIndex: index) } },
                onSelectSubtitle: { index in Task { await session.selectTranscodeSubtitle(streamIndex: index) } }
            )
        } else {
            TrackSheet(
                audio: engine.audioTracks.map(\.choice),
                selectedAudio: engine.activeAudioTrackIndex,
                subtitles: TrackSheet.subtitleChoices(engine.subtitleTracks.map(\.subtitleTrack)),
                selectedSubtitle: engine.activeSubtitleTrackIndex,
                onSelectAudio: { engine.selectAudioTrack(index: $0) },
                onSelectSubtitle: { index in
                    if let index { engine.selectSubtitleTrack(index: index) } else { engine.clearSubtitle() }
                }
            )
        }
    }
}

private extension TrackInfo {
    var subtitleTrack: SubtitleOrder.Track {
        SubtitleOrder.Track(
            id: id, language: language, title: name, codec: codec,
            isHearingImpaired: isHearingImpaired, isForced: isForced
        )
    }

    var choice: TrackChoice {
        let languageName = language.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }
        var details = [codec.uppercased()]
        if channels > 0 { details.append("\(channels)ch") }
        if isAtmos { details.append("Atmos") }
        return TrackChoice(
            id: id, title: languageName ?? (name.isEmpty ? codec.uppercased() : name),
            detail: details.joined(separator: " · ")
        )
    }
}

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            TrackSheet(
                audio: [
                    TrackChoice(id: 1, title: "English", detail: "TRUEHD · 8ch · Atmos"),
                    TrackChoice(id: 2, title: "Dutch", detail: "AC3 · 6ch"),
                ],
                selectedAudio: 1,
                subtitles: [TrackChoice(id: 3, title: "English", detail: "PGS")],
                selectedSubtitle: nil,
                onSelectAudio: { _ in }, onSelectSubtitle: { _ in }
            )
        }
        .preferredColorScheme(.dark)
}
