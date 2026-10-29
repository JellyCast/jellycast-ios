import SwiftUI

/// A Chromecast to pair: one with JellyCast open, or one paired before whose address is known.
struct PairingTarget: Identifiable, Equatable {
    let deviceID: String
    let host: String
    let name: String

    var id: String { deviceID }
}

extension PairingTarget {
    init?(_ device: RemoteDevice) {
        guard let address = device.address else { return nil }
        self.init(deviceID: device.deviceID, host: address, name: device.name)
    }

    init(_ tv: PairedTV) {
        self.init(deviceID: tv.deviceID, host: tv.host, name: tv.name)
    }
}

/// One-time pairing with a Chromecast: the TV shows a code to type here.
struct PairTVSheet: View {
    let target: PairingTarget
    let onPaired: (PairedTV) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.connecting
    @State private var code = ""
    @State private var pairing: AndroidTVPairing?
    @FocusState private var codeFocused: Bool

    private enum Phase: Equatable { case connecting, enterCode, pairing, failed(String) }

    private static let codeLength = 6
    /// The TV keeps one pairing per client name, so every phone and iPad needs its own: the same
    /// name for two devices made the second pairing replace the first.
    private static var clientName: String {
        "JellyCast \(UIDevice.current.model) \(SessionStorage.deviceID.prefix(4).uppercased())"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pair Chromecast").font(.title2.bold()).foregroundStyle(JellyCastColors.text)
                Text("Once. After that your iPhone turns the TV on and starts JellyCast, even when everything is in standby.")
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            deviceRow
            switch phase {
            case .connecting:
                Label("The code appears on the TV in a moment", systemImage: "hourglass")
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
            case .enterCode, .pairing:
                codeEntry
            case .failed(let message):
                Text(message).font(.subheadline).foregroundStyle(JellyCastColors.text)
                AccentButton(title: String(localized: "Try again"), systemImage: "arrow.clockwise") {
                    Task { await start() }
                }
            }
        }
        .padding(20)
        .task { await start() }
        .onChange(of: phase) { _, phase in
            if phase == .enterCode { codeFocused = true }
        }
        .onDisappear { pairing?.cancel() }
    }

    private var deviceRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "tv")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(JellyCastColors.accent)
                .frame(width: 40, height: 40)
                .background(JellyCastColors.accent.opacity(0.12), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.body.weight(.semibold)).foregroundStyle(JellyCastColors.text)
                Text(Format.joined(["Google TV", target.host]))
                    .font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(JellyCastColors.accent)
        }
        .padding(14)
        .background(JellyCastColors.accent.opacity(0.12), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(JellyCastColors.accent, lineWidth: 1.5))
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Type the code that is on the TV now")
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.textMuted)
            ZStack {
                TextField("", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($codeFocused)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .onChange(of: code) { _, value in
                        code = String(value.uppercased().filter(\.isHexDigit).prefix(Self.codeLength))
                    }
                HStack(spacing: 8) {
                    ForEach(0..<Self.codeLength, id: \.self) { index in
                        codeBox(index)
                    }
                }
                .contentShape(.rect)
                .onTapGesture { codeFocused = true }
            }
            AccentButton(title: String(localized: "Pair"), systemImage: "link") {
                Task { await finish() }
            }
            .disabled(code.count < Self.codeLength || phase == .pairing)
            .opacity(code.count < Self.codeLength ? 0.45 : 1)
        }
    }

    private func codeBox(_ index: Int) -> some View {
        let characters = Array(code)
        let filled = index < characters.count
        return Text(filled ? String(characters[index]) : "")
            .font(.title2.bold().monospaced())
            .foregroundStyle(JellyCastColors.text)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(JellyCastColors.text.opacity(0.08), in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(filled ? JellyCastColors.accent : JellyCastColors.text.opacity(0.1), lineWidth: 1.5)
            )
    }

    private func start() async {
        phase = .connecting
        code = ""
        pairing?.cancel()
        do {
            let pairing = try AndroidTVPairing(host: target.host)
            self.pairing = pairing
            try await pairing.start(clientName: Self.clientName)
            phase = .enterCode
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(String(localized: "The TV didn't answer. Is it on, and on this network?"))
        }
    }

    private func finish() async {
        guard let pairing else { return }
        phase = .pairing
        do {
            try await pairing.finish(code: code)
            onPaired(PairedTV(deviceID: target.deviceID, host: target.host, name: target.name))
            dismiss()
        } catch AndroidTVPairing.Failure.wrongCode {
            phase = .failed(String(localized: "That code doesn't match. Try again for a new one."))
        } catch {
            phase = .failed(String(localized: "Pairing didn't work. Try again for a new code."))
        }
    }
}
