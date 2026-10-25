import SwiftUI

struct SignInScreen: View {
    @State var model: SignInModel
    @State private var connectTask: Task<Void, Never>?
    @State private var discoveryRun = 0
    @FocusState private var addressFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                switch model.phase {
                case .enterAddress, .checkingServer, .failed:
                    DiscoverySection(
                        status: model.discovery,
                        servers: model.foundServers,
                        isConnecting: model.phase == .checkingServer,
                        onSelect: connect(to:),
                        onSearchAgain: { discoveryRun += 1 }
                    )
                    addressForm
                case .waitingForApproval(let serverName, let code):
                    QuickConnectCodeView(serverName: serverName, code: code) {
                        connectTask?.cancel()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(JellyCastColors.background)
        .task(id: discoveryRun) { await model.discover() }
        .onDisappear { connectTask?.cancel() }
    }

    private var header: some View {
        VStack(spacing: 16) {
            BrandMark().frame(width: 88, height: 88)
            BrandWordmark(size: 28)
        }
    }

    private var addressForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.foundServers.isEmpty ? "Server address" : "Or enter the address")
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.textMuted)
            TextField("192.168.1.4:8096", text: $model.address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit(connect)
                .padding(14)
                .background(JellyCastColors.surface, in: .rect(cornerRadius: 12))
                .foregroundStyle(JellyCastColors.text)
            if case .failed(let message) = model.phase {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button(action: connect) {
                HStack {
                    if model.phase == .checkingServer { ProgressView().tint(JellyCastColors.text) }
                    Text("Connect").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(JellyCastColors.primaryContainer)
            .disabled(!model.canConnect || model.phase == .checkingServer)
            .padding(.top, 8)
        }
    }

    private func connect() {
        guard model.canConnect else { return }
        addressFocused = false
        connectTask?.cancel()
        connectTask = Task { await model.connect() }
    }

    private func connect(to server: DiscoveredServer) {
        addressFocused = false
        connectTask?.cancel()
        connectTask = Task { await model.connect(to: server) }
    }
}

private struct DiscoverySection: View {
    let status: SignInModel.DiscoveryStatus
    let servers: [SignInModel.FoundServer]
    let isConnecting: Bool
    let onSelect: (DiscoveredServer) -> Void
    let onSearchAgain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Servers on your network")
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
                Spacer()
                if status == .searching { ProgressView().tint(JellyCastColors.textMuted) }
            }
            ForEach(servers) { found in
                Button { onSelect(found.server) } label: { ServerRow(found: found) }
                    .buttonStyle(.plain)
                    .disabled(isConnecting)
            }
            if servers.isEmpty {
                Text(emptyMessage)
                    .font(.footnote)
                    .foregroundStyle(JellyCastColors.textMuted)
                if status == .done {
                    Button("Search again", systemImage: "arrow.clockwise", action: onSearchAgain)
                        .buttonStyle(.glass)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: LocalizedStringKey {
        status == .searching
            ? "Looking for servers on your network…"
            : "No Jellyfin server found on your network. Enter its address yourself, or search again."
    }
}

private struct ServerRow: View {
    let found: SignInModel.FoundServer

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(found.server.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(JellyCastColors.text)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(JellyCastColors.textMuted)
            }
            Spacer(minLength: 8)
            if found.isCurrent {
                Text("Current")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JellyCastColors.accent)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JellyCastColors.textMuted)
        }
        .padding(14)
        .background(JellyCastColors.surface, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
    }

    private var detail: String {
        let address = found.server.serverURL.host(percentEncoded: false).map { host in
            found.server.serverURL.port.map { "\(host):\($0)" } ?? host
        } ?? found.server.serverURL.absoluteString
        return switch found.check {
        case .checking: address
        case .ready(let version): String(localized: "\(address) · Jellyfin \(version)")
        case .unreachable: String(localized: "\(address) · not responding")
        }
    }
}

private struct QuickConnectCodeView: View {
    let serverName: String
    let code: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Sign in to \(serverName)")
                .font(.headline)
                .foregroundStyle(JellyCastColors.text)
            Text(code)
                .font(.system(size: 44, weight: .bold).monospacedDigit())
                .tracking(6)
                .foregroundStyle(JellyCastColors.text)
                .textSelection(.enabled)
            Text("In Jellyfin, open your profile, choose Quick Connect and enter this code.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(JellyCastColors.textMuted)
            ProgressView().tint(JellyCastColors.textMuted)
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.glass)
        }
    }
}

#Preview("Address") {
    SignInScreen(model: SignInModel(address: "192.168.1.4:8096") { _ in })
}

#Preview("Discovered") {
    DiscoverySection(
        status: .done,
        servers: [
            SignInModel.FoundServer(
                server: DiscoveredServer(
                    id: "a", name: "home server", serverURL: URL(string: "http://192.168.1.4:8096")!
                ),
                check: .ready(version: "10.11.2"),
                isCurrent: true
            ),
            SignInModel.FoundServer(
                server: DiscoveredServer(
                    id: "b", name: "nas", serverURL: URL(string: "http://192.168.1.20:8096")!
                ),
                check: .unreachable,
                isCurrent: false
            ),
        ],
        isConnecting: false,
        onSelect: { _ in },
        onSearchAgain: {}
    )
    .padding()
    .background(JellyCastColors.background)
}

#Preview("Code") {
    QuickConnectCodeView(serverName: "home server", code: "804134") {}
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JellyCastColors.background)
}
