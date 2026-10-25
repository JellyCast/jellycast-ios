import SwiftUI

/// "Download next 5" on the series page: the next unwatched episodes in order, after showing
/// what they take. The series then stays ahead when that setting is on.
struct DownloadNextButton: View {
    let series: Series
    let progress: SeriesProgress
    var size: CGFloat = 34

    @State private var plans: [(episode: Episode, kind: DownloadKind, bytes: Int64?)] = []
    @State private var showsConfirmation = false
    @State private var isPreparing = false
    @State private var message: String?

    private var store: DownloadStore { .shared }

    var body: some View {
        let missing = store.missingEpisodes(progress)
        let upcoming = DownloadStore.upcomingEpisodes(progress, count: DownloadSettings.seriesBatch)
        Button(action: tapped) {
            ZStack {
                Circle().fill(JellyCastColors.rail)
                if isPreparing {
                    ProgressView().tint(JellyCastColors.text)
                } else {
                    Image(systemName: missing.isEmpty ? "arrow.down.circle.fill" : "arrow.down.to.line")
                        .font(.system(size: missing.isEmpty ? 22 : 16, weight: .bold))
                        .foregroundStyle(missing.isEmpty ? JellyCastColors.accent : JellyCastColors.text)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .disabled(missing.isEmpty || isPreparing)
        .opacity(upcoming.isEmpty ? 0 : 1)
        .accessibilityLabel(missing.isEmpty
            ? Text("Next episodes are on this device") : Text("Download next \(missing.count)"))
        .confirmationDialog(dialogTitle, isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("Download \(plans.count) episodes") { confirm() }
        } message: {
            Text(dialogMessage)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
    }

    private func tapped() {
        Task {
            isPreparing = true
            defer { isPreparing = false }
            if !store.canReachServer { await store.recheckServer() }
            guard store.canReachServer else {
                message = String(localized: "Downloading only works at home, where the server is.")
                return
            }
            plans = await store.plans(for: store.missingEpisodes(progress))
            guard !plans.isEmpty else { return }
            showsConfirmation = true
        }
    }

    private func confirm() {
        let queued = store.enqueue(plans)
        DownloadSettings.shared.keep(seriesID: series.id)
        if queued < plans.count {
            message = String(localized: "Only \(queued) of \(plans.count) fit on this device.")
        }
    }

    private var dialogTitle: Text {
        Text(series.name)
    }

    private var dialogMessage: String {
        let range = [plans.first, plans.last].compactMap { $0.map { Format.seasonEpisode($0.episode) } }
        let total = plans.reduce(Int64(0)) { $0 + ($1.bytes ?? 0) }
        return Format.joined([
            Set(range).count > 1 ? range.joined(separator: " – ") : range.first,
            String(localized: "about \(DownloadFormat.bytes(total))"),
            store.freeBytes.map { String(localized: "Free \(DownloadFormat.bytes($0))") },
        ])
    }
}
