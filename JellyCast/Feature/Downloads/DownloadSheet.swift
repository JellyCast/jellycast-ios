import SwiftUI

/// Compact or Original for one item, with the size of each and the free space.
struct DownloadSheet: View {
    let playable: Playable

    @Environment(\.dismiss) private var dismiss
    @State private var plan: DownloadPlan?
    @State private var info: MediaInfo?
    @State private var chosen = DownloadKind.compact

    /// Measured: 4K HDR to 1080p ran at ~6.6×, 1080p SDR at ~10×; the slow end is used.
    private static let conversionSpeed = 6.0
    /// The background session's speed from the server on the home Wi-Fi (~317 Mbit/s measured).
    private static let assumedDownloadBytesPerSecond = 300_000_000.0 / 8

    private var store: DownloadStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download \(DownloadStore.title(of: playable))")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(JellyCastColors.text)
                if let free = store.freeBytes {
                    Text("Free on this \(UIDevice.current.localizedModel): \(DownloadFormat.bytes(free))")
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.textMuted)
                }
            }
            if let plan {
                options(plan)
                downloadButton(plan)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
        .presentationBackground(JellyCastColors.surface)
        .task {
            let result = await store.plan(for: playable)
            info = result.info
            chosen = result.plan.defaultKind
            plan = result.plan
        }
    }

    @ViewBuilder
    private func options(_ plan: DownloadPlan) -> some View {
        if plan.offersCompact {
            option(.compact, plan: plan, description: compactDescription)
        }
        option(.original, plan: plan, description: originalDescription(plan))
    }

    private func option(_ kind: DownloadKind, plan: DownloadPlan, description: String) -> some View {
        let bytes = plan.bytes(for: kind)
        let shortage = shortage(bytes)
        let isChosen = chosen == kind
        return Button {
            chosen = kind
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isChosen ? JellyCastColors.accent : JellyCastColors.textMuted)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(kind == .compact ? "Compact" : "Original").font(.headline)
                        Spacer()
                        if let bytes {
                            Text(kind == .compact ? DownloadFormat.estimate(bytes) : DownloadFormat.bytes(bytes))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(JellyCastColors.text)
                    Text(shortage.map { String(localized: "Doesn't fit · \(DownloadFormat.bytes($0)) more needed") }
                        ?? description)
                        .font(.subheadline)
                        .foregroundStyle(shortage == nil ? JellyCastColors.textMuted : .orange)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .background(
                isChosen ? JellyCastColors.accent.opacity(0.12) : JellyCastColors.text.opacity(0.05),
                in: .rect(cornerRadius: 18)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isChosen ? JellyCastColors.accent : JellyCastColors.text.opacity(0.1), lineWidth: 1.5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .disabled(shortage != nil)
        .opacity(shortage == nil ? 1 : 0.6)
    }

    @ViewBuilder
    private func downloadButton(_ plan: DownloadPlan) -> some View {
        let bytes = plan.bytes(for: chosen)
        let fits = shortage(bytes) == nil
        AccentButton(
            title: String(localized: "Download"),
            detail: bytes.map { chosen == .compact ? DownloadFormat.estimate($0) : DownloadFormat.bytes($0) },
            systemImage: "arrow.down.to.line"
        ) {
            store.enqueue(playable, kind: chosen, estimatedBytes: bytes)
            dismiss()
        }
        .disabled(!fits)
        .opacity(fits ? 1 : 0.5)
    }

    private func shortage(_ bytes: Int64?) -> Int64? {
        guard let bytes, let free = store.freeBytes, bytes > free else { return nil }
        return bytes - free
    }

    private var compactDescription: String {
        let seconds = playable.runtimeTicks.map(Ticks.seconds) ?? 0
        let minutes = max(Int((seconds / Self.conversionSpeed / 60).rounded(.up)), 1)
        return String(localized: "1080p, standard colours (SDR), one audio track in stereo. The server converts it: ready in about \(minutes) min.")
    }

    private func originalDescription(_ plan: DownloadPlan) -> String {
        let tech = info.map { TechLine.parts(for: $0).joined(separator: ", ") }
        let bytesPerSecond = ConnectionMeter.shared.freshBytesPerSecond ?? Self.assumedDownloadBytesPerSecond
        let minutes = plan.originalBytes.map { max(Int((Double($0) / bytesPerSecond / 60).rounded(.up)), 1) }
        return [
            tech.map { String(localized: "\($0), every audio and subtitle track.") },
            minutes.map { String(localized: "About \($0) min to download.") },
        ].compactMap(\.self).joined(separator: " ")
    }
}
