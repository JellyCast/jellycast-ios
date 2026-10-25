import SwiftUI

/// The AI service and its API key. Without a key the player has no Chat tab.
struct AIChatSettingsScreen: View {
    @Bindable var settings: ChatSettings

    @State private var draftKey = ""
    @State private var isEditing = false
    @State private var check = KeyCheck.idle

    private enum KeyCheck: Equatable {
        case idle, checking, valid
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Service") {
                Picker("Service", selection: $settings.provider) {
                    ForEach(ChatProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                keyField
                if settings.hasKey, !isEditing {
                    Button { Task { await testKey() } } label: {
                        HStack {
                            Text("Test key")
                            Spacer()
                            checkStatus
                        }
                    }
                    .disabled(check == .checking)
                    Button("Remove key", role: .destructive) {
                        settings.setKey(nil)
                        check = .idle
                    }
                }
            } header: {
                Text("API key")
            } footer: {
                Text("The key is stored in the Keychain on this device only. Without a key there is no Chat tab.")
            }
            Section {
                Toggle("Search the web", isOn: $settings.searchesWeb)
            } footer: {
                Text("The model can look things up, such as real events behind the story or news about the cast, and shows its sources. Searches cost a little extra on your API account.")
            }
            Section {
                Toggle("No spoilers", isOn: $settings.avoidsSpoilers)
            } footer: {
                Text("The model is told what you have watched so far and instructed not to reveal anything after it.")
            }
        }
        .navigationTitle("AI chat")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: settings.provider) {
            isEditing = false
            draftKey = ""
            check = .idle
        }
    }

    @ViewBuilder
    private var keyField: some View {
        if let masked = settings.maskedKey, !isEditing {
            HStack {
                Text(verbatim: masked).font(.body.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Change") { isEditing = true }
            }
        } else {
            SecureField(placeholder, text: $draftKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(save)
            Button("Save key", action: save)
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var checkStatus: some View {
        switch check {
        case .idle: EmptyView()
        case .checking: ProgressView()
        case .valid: Image(systemName: "checkmark.circle.fill").foregroundStyle(JellyCastColors.accent)
        case .failed(let message): Text(message).font(.footnote).foregroundStyle(.orange)
        }
    }

    private var placeholder: String {
        switch settings.provider {
        case .claude: "sk-ant-…"
        case .openAI: "sk-…"
        }
    }

    private func save() {
        settings.setKey(draftKey)
        draftKey = ""
        isEditing = false
        Task { await testKey() }
    }

    private func testKey() async {
        guard let client = settings.client() else { return }
        check = .checking
        do {
            try await client.check()
            check = .valid
        } catch ChatError.invalidKey {
            check = .failed(String(localized: "Not accepted"))
        } catch let error as ChatError {
            check = .failed(error.message)
        } catch is CancellationError {
            check = .idle
        } catch {
            check = .failed(ChatError.unavailable(0).message)
        }
    }
}

#Preview {
    NavigationStack { AIChatSettingsScreen(settings: .shared) }
        .preferredColorScheme(.dark)
}
