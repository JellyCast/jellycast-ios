import SwiftUI

/// The addresses of the signed-in server, such as the LAN address and one over a VPN.
struct ServerAddressesScreen: View {
    let store: LibraryStore

    @State private var model = ServerAddressesModel()
    @State private var showsAddAddress = false
    @State private var newAddress = ""

    var body: some View {
        List {
            Section {
                ForEach(store.addresses, id: \.self) { address in
                    addressRow(address)
                }
                .onMove { from, to in
                    var updated = store.addresses
                    updated.move(fromOffsets: from, toOffset: to)
                    model.reorder(updated, store: store)
                }
                .onDelete { offsets in
                    var updated = store.addresses
                    updated.remove(atOffsets: offsets)
                    model.reorder(updated, store: store)
                }
                .deleteDisabled(store.addresses.count < 2)
            } footer: {
                Text("JellyCast uses the first address from the top that answers. Tap Edit to change the order.")
            }
            Section {
                Button {
                    newAddress = ""
                    showsAddAddress = true
                } label: {
                    HStack {
                        Text("Add address")
                        Spacer()
                        if model.isAdding { ProgressView() }
                    }
                }
                .disabled(model.isAdding)
                if let message = model.message {
                    Text(message).foregroundStyle(.orange)
                }
            } footer: {
                Text("Add another address of \(store.session.serverName), for example over your VPN. You stay signed in.")
            }
        }
        .navigationTitle("Addresses")
        .toolbar { EditButton() }
        .alert("Add address", isPresented: $showsAddAddress) {
            TextField("Address", text: $newAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") { Task { await model.add(newAddress, store: store) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("For example 10.8.0.1:8096")
        }
    }

    private func addressRow(_ address: URL) -> some View {
        Button {
            Task { await model.use(address, store: store) }
        } label: {
            HStack {
                Text(Self.title(of: address))
                    .foregroundStyle(JellyCastColors.text)
                Spacer()
                if model.checking == address {
                    ProgressView()
                } else if address == store.session.serverURL {
                    Text("In use").foregroundStyle(JellyCastColors.textMuted)
                }
            }
        }
        .disabled(model.checking != nil)
    }

    /// "192.168.1.4:8096" for a plain HTTP address, the full URL otherwise.
    static func title(of address: URL) -> String {
        guard address.scheme == "http", address.path().isEmpty || address.path() == "/",
              let host = address.host(percentEncoded: false)
        else { return address.absoluteString }
        return address.port.map { "\(host):\($0)" } ?? host
    }
}

@Observable
final class ServerAddressesModel {
    private(set) var checking: URL?
    private(set) var isAdding = false
    private(set) var message: String?

    private static let checkTimeoutSeconds = 5.0

    func use(_ address: URL, store: LibraryStore) async {
        guard address != store.session.serverURL else { return }
        message = nil
        checking = address
        defer { checking = nil }
        let probe = await ServerAddressPicker.probe(
            address, serverID: store.session.serverID, timeoutSeconds: Self.checkTimeoutSeconds
        )
        guard probe.reached else {
            message = String(localized: "The server doesn't answer on this address right now.")
            return
        }
        store.use(address)
    }

    func reorder(_ addresses: [URL], store: LibraryStore) {
        message = nil
        store.setAddresses(addresses)
        Task { await store.checkServer(reportsProblem: false) }
    }

    func add(_ text: String, store: LibraryStore) async {
        message = nil
        guard let address = JellyfinClient.serverURL(from: text) else {
            message = JellyfinError.invalidAddress.localizedDescription
            return
        }
        guard !store.addresses.contains(address) else {
            message = String(localized: "This address is already in the list.")
            return
        }
        isAdding = true
        defer { isAdding = false }
        let client = JellyfinClient(serverURL: address, deviceID: SessionStorage.deviceID)
        do {
            let info = try await client.publicInfo(timeout: Self.checkTimeoutSeconds)
            guard info.id == store.session.serverID else {
                message = String(localized: "This address leads to another server: \(info.name).")
                return
            }
            store.setAddresses(store.addresses + [address])
        } catch is CancellationError {
        } catch {
            message = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ServerAddressesScreen(store: LibraryStore(session: .preview, snapshot: .preview))
    }
    .preferredColorScheme(.dark)
}
