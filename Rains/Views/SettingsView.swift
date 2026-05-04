import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var connectionState: ConnectionState = .idle

    enum ConnectionState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                appearanceSection
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitURL()
                        dismiss()
                    }
                }
            }
            .onAppear { urlInput = appState.serverURL.absoluteString }
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        @Bindable var bindable = appState

        Section {
            TextField("http://localhost:11434", text: $urlInput)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .urlKeyboard()
                .onSubmit { commitURL() }

            Button {
                test()
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    if connectionState == .testing {
                        ProgressView()
                    }
                }
            }
            .disabled(connectionState == .testing)

            connectionStatusRow
        } header: {
            Text("Server")
        } footer: {
            Text("URL of your Ollama server. Default: http://localhost:11434")
        }
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        switch connectionState {
        case .idle, .testing:
            EmptyView()
        case .success(let count):
            Label("\(count) model\(count == 1 ? "" : "s") available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        @Bindable var bindable = appState

        Section("Appearance") {
            Picker("Theme", selection: $bindable.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
        }
    }

    private func commitURL() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        if url != appState.serverURL {
            appState.serverURL = url
            connectionState = .idle
        }
    }

    private func test() {
        commitURL()
        let client = appState.client
        connectionState = .testing
        Task {
            do {
                let models = try await client.listModels()
                connectionState = .success(models.count)
            } catch {
                connectionState = .failure(error.localizedDescription)
            }
        }
    }
}
