import SwiftUI

/// The round download button of a movie or episode. A movie asks first in the download sheet; an
/// episode starts at once with the default choice, and a long press opens the sheet.
struct DownloadButton: View {
    let playable: Playable
    var size: CGFloat = 34

    @State private var showsSheet = false
    @State private var message: String?
    @State private var isPreparing = false

    private var store: DownloadStore { .shared }
    private var download: Download? { store.download(for: playable.id) }

    private var asksFirst: Bool {
        if case .movie = playable { return true }
        return false
    }

    var body: some View {
        Group {
            if let download {
                Menu {
                    menuItems(for: download)
                } label: {
                    DownloadStateIcon(download: download, size: size)
                }
                .menuStyle(.button)
                .buttonStyle(PressedOpacityButtonStyle())
            } else {
                Button(action: tapped) {
                    DownloadStateIcon(download: nil, size: size, isPreparing: isPreparing)
                        .opacity(store.canReachServer ? 1 : Self.awayOpacity)
                }
                .buttonStyle(PressedOpacityButtonStyle())
                .contextMenu {
                    if !asksFirst && store.canReachServer {
                        Button("Download options…", systemImage: "slider.horizontal.3") { showsSheet = true }
                    }
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $showsSheet) {
            DownloadSheet(playable: playable)
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
    }

    private static let awayOpacity = 0.4

    @ViewBuilder
    private func menuItems(for download: Download) -> some View {
        switch download.status {
        case .done:
            Button("Remove download", systemImage: "trash", role: .destructive) { store.remove(download.id) }
        case .paused, .failed:
            Button("Go on", systemImage: "arrow.down") { store.resume(download.id) }
            Button("Cancel download", systemImage: "xmark", role: .destructive) { store.remove(download.id) }
        case .queued, .running, .waitingForNetwork:
            Button("Pause", systemImage: "pause") { store.pause(download.id) }
            Button("Cancel download", systemImage: "xmark", role: .destructive) { store.remove(download.id) }
        }
    }

    private func tapped() {
        Task {
            if !store.canReachServer {
                isPreparing = true
                await store.recheckServer()
                isPreparing = false
            }
            guard store.canReachServer else {
                message = String(localized: "Downloading only works at home, where the server is.")
                return
            }
            if asksFirst {
                showsSheet = true
            } else {
                await startDefault()
            }
        }
    }

    /// An episode starts without the sheet: Compact, or the original when that is no bigger.
    private func startDefault() async {
        isPreparing = true
        defer { isPreparing = false }
        let plan = await store.plan(for: playable).plan
        let kind = plan.defaultKind
        let bytes = plan.bytes(for: kind)
        if let bytes, let free = store.freeBytes, bytes > free {
            message = String(localized: "This doesn't fit: \(DownloadFormat.bytes(bytes - free)) more is needed.")
            return
        }
        store.enqueue(playable, kind: kind, estimatedBytes: bytes)
    }

    private var accessibilityLabel: Text {
        guard let download else { return Text("Download") }
        return Text(DownloadFormat.statusLine(download, secondsLeft: nil))
    }
}

/// The five looks of the download button: not downloaded, waiting, running with its progress,
/// paused or failed, and on this iPhone.
struct DownloadStateIcon: View {
    let download: Download?
    var size: CGFloat = 34
    var isPreparing = false

    private static let ringInset: CGFloat = 5
    private static let ringWidth: CGFloat = 2.5
    private static let queuedDash: [CGFloat] = [3, 4.5]

    var body: some View {
        ZStack {
            Circle().fill(JellyCastColors.rail)
            content
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        if isPreparing {
            ProgressView().controlSize(.small).tint(JellyCastColors.text)
        } else if let download {
            switch download.status {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(JellyCastColors.accent)
            case .queued:
                ring(dash: Self.queuedDash, fraction: nil)
                symbol("clock")
            case .running, .waitingForNetwork:
                ring(dash: nil, fraction: download.fraction ?? 0)
                Image(systemName: download.status == .running ? "stop.fill" : "wifi.slash")
                    .font(.system(size: download.status == .running ? 9 : 11, weight: .bold))
                    .foregroundStyle(JellyCastColors.text)
            case .paused:
                ring(dash: nil, fraction: download.fraction ?? 0)
                symbol("arrow.down")
            case .failed:
                symbol("exclamationmark")
            }
        } else {
            symbol("arrow.down.to.line")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(JellyCastColors.text)
    }

    private func ring(dash: [CGFloat]?, fraction: Double?) -> some View {
        ZStack {
            Circle()
                .stroke(
                    JellyCastColors.text.opacity(0.2),
                    style: StrokeStyle(lineWidth: Self.ringWidth, dash: dash ?? [])
                )
            if let fraction {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(JellyCastColors.accent, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(Self.ringInset)
    }
}

#Preview {
    let episode = LibrarySnapshot.preview.episodes[0]
    HStack(spacing: 16) {
        DownloadStateIcon(download: nil)
        DownloadStateIcon(download: Download(playable: .episode(episode), kind: .compact))
        DownloadStateIcon(download: Download(
            playable: .episode(episode), kind: .compact, status: .running, mediaSeconds: 42, totalMediaSeconds: 100
        ))
        DownloadStateIcon(download: Download(playable: .episode(episode), kind: .compact, status: .done))
    }
    .padding()
    .background(JellyCastColors.background)
    .preferredColorScheme(.dark)
}
