import SwiftUI

/// The TV button next to play. It stays put even when no TV is reachable: pairing a Chromecast
/// moves JellyCast on it to the background, which drops it from the list while the sheet is open.
struct PlayOnButton: View {
    let playable: Playable
    var size: CGFloat = 52

    @Environment(RemoteSessions.self) private var remote: RemoteSessions?
    @Environment(AppNavigation.self) private var navigation
    @State private var showsSheet = false

    var body: some View {
        if let remote {
            RailCircleButton(systemImage: "tv", label: "Play on…", size: size) { showsSheet = true }
                .sheet(isPresented: $showsSheet) {
                    PlayOnSheet(playable: playable, remote: remote) { navigation.play(playable) }
                }
        }
    }
}

/// Where to play: the TVs that take commands, and this iPhone. One tap starts it. With
/// `handOffTicks` it continues what plays now from there: from the player (no "This iPhone"),
/// or from a TV (not that TV itself).
struct PlayOnSheet: View {
    let playable: Playable
    let remote: RemoteSessions
    var handOffTicks: Int64?
    /// The tracks that play now, so the TV continues with the same ones.
    var handOffStreams: StreamSelection?
    /// The TV that plays it now.
    var excludedDeviceID: String?
    /// `nil` when continuing from the player.
    let onPlayHere: (() -> Void)?
    var onHandOff: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: (deviceID: String, name: String)?
    @State private var newName = ""
    @State private var pairingDevice: RemoteDevice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetTitle(
                    title: handOffTicks == nil
                        ? String(localized: "Play \(playable.name) on")
                        : String(localized: "Continue \(playable.name) on"),
                    subtitle: resumeLabel
                )
                ForEach(devices) { device in
                    row(
                        title: device.name, detail: deviceDetail(device), systemImage: "tv", isAccented: true
                    ) {
                        play(on: device)
                    }
                    .contextMenu { menu(deviceID: device.deviceID, name: device.name) }
                }
                ForEach(wakeableTVs) { tv in
                    row(
                        title: tv.name, detail: String(localized: "Asleep · turns the TV on"),
                        systemImage: "tv", isAccented: true
                    ) {
                        wake(tv)
                    }
                    .contextMenu { menu(deviceID: tv.deviceID, name: tv.name) }
                }
                if let onPlayHere {
                    row(title: String(localized: "This iPhone"), detail: nil, systemImage: "iphone", isAccented: false) {
                        dismiss()
                        onPlayHere()
                    }
                }
                if remote.hasUnreachablePairedTV {
                    Text("Your Chromecast can only be reached from your home network.")
                        .font(.footnote)
                        .foregroundStyle(JellyCastColors.textMuted)
                        .padding(.horizontal, 4)
                }
                if devices.isEmpty && wakeableTVs.isEmpty {
                    Text("No TV can be reached now. Open JellyCast on a TV to play there.")
                        .font(.subheadline)
                        .foregroundStyle(JellyCastColors.text)
                        .padding(.horizontal, 4)
                }
                Text("Is your TV missing? Open JellyCast on that TV.")
                    .font(.footnote)
                    .foregroundStyle(JellyCastColors.textMuted)
                    .padding(.horizontal, 4)
                if let pairable = remote.pairableTVs.first {
                    Button("Pair Chromecast") { pairingDevice = pairable }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JellyCastColors.accent)
                        .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await remote.checkReachability() }
        .sheet(item: $pairingDevice) { device in
            PairTVSheet(device: device) { remote.paired.add($0) }
                .presentationDetents([.medium, .large])
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let renaming { remote.rename(deviceID: renaming.deviceID, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The name is only used on this iPhone.")
        }
    }

    private var devices: [RemoteDevice] {
        remote.playableDevices.filter { $0.deviceID != excludedDeviceID }
    }

    private var wakeableTVs: [PairedTV] {
        remote.wakeableTVs.filter { $0.deviceID != excludedDeviceID }
    }

    private var startTicks: Int64 {
        handOffTicks ?? (playable.watch.played ? 0 : playable.watch.positionTicks)
    }

    private var resumeLabel: String? {
        guard startTicks > 0 else { return nil }
        return String(localized: "Continues from \(RemoteFormat.clock(startTicks))")
    }

    private func deviceDetail(_ device: RemoteDevice) -> String {
        device.isPlaying ? String(localized: "Playing something else now") : String(localized: "JellyCast is open")
    }

    @ViewBuilder
    private func menu(deviceID: String, name: String) -> some View {
        Button("Rename", systemImage: "pencil") {
            newName = name
            renaming = (deviceID, name)
        }
        if remote.paired.contains(deviceID) {
            Button("Forget pairing", systemImage: "link.badge.minus", role: .destructive) {
                remote.paired.forget(deviceID)
            }
        }
    }

    private func wake(_ tv: PairedTV) {
        dismiss()
        onHandOff()
        Task {
            await remote.wakeAndPlay(tv, itemID: playable.id, startTicks: startTicks, streams: handOffStreams)
        }
    }

    private func play(on device: RemoteDevice) {
        // Only the remote protocol can turn the TV on, which may be off while JellyCast is open.
        if let tv = remote.paired.all.first(where: { $0.deviceID == device.deviceID }) {
            return wake(tv)
        }
        dismiss()
        onHandOff()
        let command = RemoteCommand.play(itemID: playable.id, startTicks: startTicks, streams: handOffStreams)
        Task { await remote.send(command, to: device.id) }
    }

    private func row(
        title: String, detail: String?, systemImage: String, isAccented: Bool, action: @escaping () -> Void
    ) -> some View {
        SheetRow(title: title, detail: detail, systemImage: systemImage, isAccented: isAccented, action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(JellyCastColors.text)
        }
    }
}
