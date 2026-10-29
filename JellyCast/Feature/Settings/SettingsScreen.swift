import SwiftUI

/// Server, account and library status, behind the profile button on Kijken.
struct SettingsScreen: View {
    let store: LibraryStore
    let onSignOut: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Server", value: store.session.serverName)
                    LabeledContent("Address", value: store.session.serverURL.absoluteString)
                    LabeledContent("Signed in as", value: store.session.userName)
                }
                Section("Library") {
                    if let snapshot = store.snapshot {
                        LabeledContent("Movies", value: snapshot.movies.count, format: .number)
                        LabeledContent("Series", value: snapshot.series.count, format: .number)
                        LabeledContent("Episodes", value: snapshot.episodes.count, format: .number)
                        LabeledContent("Updated") {
                            Text(snapshot.syncedAt, format: .relative(presentation: .named))
                        }
                    }
                    if case .failed(let message) = store.syncState {
                        Text(message).foregroundStyle(.orange)
                    }
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        HStack {
                            Text("Refresh library")
                            Spacer()
                            if store.syncState == .syncing { ProgressView() }
                        }
                    }
                    .disabled(store.syncState == .syncing)
                }
                StreamingQualitySection(
                    settings: QualitySettings.shared, network: NetworkMonitor.shared,
                    serverURL: store.session.serverURL
                )
                AudioDelaySettingsSection(delay: AudioOutputDelay.shared)
                DownloadSettingsSection(settings: DownloadSettings.shared)
                RatingSettingsSection(settings: RatingSettings.shared)
                Section {
                    NavigationLink {
                        AIChatSettingsScreen(settings: ChatSettings.shared)
                    } label: {
                        LabeledContent("AI chat", value: ChatSettings.shared.hasKey
                            ? ChatSettings.shared.provider.title : String(localized: "Off"))
                    }
                }
                if let timings {
                    Section("Developer") {
                        LabeledContent("Timings", value: timings)
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        dismiss()
                        onSignOut()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var timings: String? {
        let parts = [
            store.cacheLoadDuration.map { "cache \(Self.milliseconds($0))" },
            store.lastSyncDuration.map { "sync \(Self.milliseconds($0))" },
        ].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func milliseconds(_ duration: Duration) -> String {
        "\(Int(duration / .milliseconds(1))) ms"
    }
}

private struct RatingSettingsSection: View {
    @Bindable var settings: RatingSettings

    var body: some View {
        Section {
            Picker("Rating and links", selection: $settings.source) {
                ForEach(RatingSource.allCases, id: \.self) { source in
                    Text(verbatim: source.title).tag(source)
                }
            }
        } header: {
            Text("Ratings")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        switch settings.source {
        case .imdb:
            String(localized: """
                The IMDb rating of movies and series, with links to IMDb. Descriptions come from IMDb.
                """)
        case .rottenTomatoes:
            String(localized: """
                The Rotten Tomatoes critics' score, which the server has for movies only. Links search \
                Rotten Tomatoes. Descriptions come from IMDb.
                """)
        case .tmdb:
            String(localized: """
                Links to TMDB. The server keeps a TMDB rating for episodes only. Descriptions come from IMDb.
                """)
        }
    }
}

/// The lip-sync corrections set in the player, per Bluetooth device; here only to look back at.
private struct AudioDelaySettingsSection: View {
    let delay: AudioOutputDelay

    var body: some View {
        Section {
            if delay.saved.isEmpty {
                Text("None yet").foregroundStyle(JellyCastColors.textMuted)
            }
            ForEach(delay.saved.sorted { $0.value.name < $1.value.name }, id: \.key) { id, device in
                LabeledContent(device.name, value: "\(device.milliseconds) ms")
                    .swipeActions {
                        Button("Remove", role: .destructive) { delay.remove(id: id) }
                    }
            }
        } header: {
            Text("Bluetooth sound delay")
        } footer: {
            Text("""
                Set in the player, under Audio and subtitles, while the device plays. It applies \
                whenever that device plays again.
                """)
        }
    }
}

private struct DownloadSettingsSection: View {
    @Bindable var settings: DownloadSettings

    var body: some View {
        Section {
            Toggle("Remove watched downloads", isOn: $settings.removesWatched)
            Toggle("Keep series ahead", isOn: $settings.keepsSeriesAhead)
        } header: {
            Text("Downloads")
        } footer: {
            Text("""
                Watched downloads go a day after you watched them. A series you downloaded with \
                Download next keeps its next \(DownloadSettings.seriesBatch) episodes on this device: \
                at home, the next one downloads once you watch one.
                """)
        }
    }
}

/// The default quality per network; the player can still change it for one play.
private struct StreamingQualitySection: View {
    @Bindable var settings: QualitySettings
    let network: NetworkMonitor
    let serverURL: URL

    var body: some View {
        Section {
            picker("Local network", selection: $settings.local)
            picker("Wi-Fi", selection: $settings.wifi)
            picker("Mobile data", selection: $settings.cellular)
            LabeledContent("Now on", value: nowOn)
        } header: {
            Text("Streaming quality")
        } footer: {
            Text("""
                Local network is when the server is on the same network as this \(UIDevice.current.localizedModel). \
                Auto measures the connection when playback starts and picks the highest quality \
                that keeps up. Below Original the server converts the video, in SDR.
                """)
        }
    }

    private var nowOn: String {
        switch network.kind(serverURL: serverURL) {
        case .local: String(localized: "Local network")
        case .wifi: "Wi-Fi"
        case .cellular: String(localized: "Mobile data")
        }
    }

    private func picker(_ title: LocalizedStringKey, selection: Binding<QualityPreference>) -> some View {
        Picker(title, selection: selection) {
            ForEach(QualityPreference.all, id: \.self) { preference in
                Text(preference.title).tag(preference)
            }
        }
    }
}

#Preview {
    SettingsScreen(store: LibraryStore(session: .preview, snapshot: .preview)) {}
        .preferredColorScheme(.dark)
}
