import SwiftUI

struct NewChatSheet: View {
    let onCreate: (String) -> Void
    var initialMessage: String = ""

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var loadState: LoadState = .loading
    @State private var selectedModel: String = ""
    @State private var manualEntry: Bool = false
    @State private var manualName: String = ""

    enum LoadState: Equatable {
        case loading
        case loaded([OllamaModel])
        case failed(String)
    }

    init(onCreate: @escaping (String) -> Void, initialMessage: String = "") {
        self.onCreate = onCreate
        self.initialMessage = initialMessage
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if manualEntry {
                        TextField("e.g. llama3.2", text: $manualName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        modelPickerRow
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text(footerText)
                }

                if case .failed = loadState, !manualEntry {
                    Section {
                        Button("Enter model name manually") { manualEntry = true }
                    }
                }

                if !manualEntry, case .loaded = loadState {
                    Section {
                        Button("Type a model name instead") { manualEntry = true }
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            .task { await loadModels() }
        }
    }

    @ViewBuilder
    private var modelPickerRow: some View {
        switch loadState {
        case .loading:
            HStack {
                Text("Loading models…").foregroundStyle(.secondary)
                Spacer()
                ProgressView()
            }
        case .loaded(let models):
            if models.isEmpty {
                Text("No models installed on the server").foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $selectedModel) {
                    ForEach(models) { model in
                        ModelLabel(model: model).tag(model.name)
                    }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Couldn't load models", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var footerText: String {
        switch (manualEntry, loadState) {
        case (true, _):
            return "Type the name of a model already pulled on your Ollama server."
        case (_, .loaded):
            return "Picked from /api/tags on \(appState.serverURL.host() ?? appState.serverURL.absoluteString)."
        case (_, .loading):
            return "Reading models from your Ollama server…"
        case (_, .failed):
            return "If the server is unreachable you can still create a chat by typing a model name."
        }
    }

    private var canCreate: Bool {
        if manualEntry {
            return !manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !selectedModel.isEmpty
    }

    private func create() {
        let chosen = manualEntry
            ? manualName.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedModel
        guard !chosen.isEmpty else { return }
        onCreate(chosen)
        dismiss()
    }

    private func loadModels() async {
        loadState = .loading
        do {
            let models = try await appState.client.listModels()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            loadState = .loaded(models)
            if selectedModel.isEmpty, let first = models.first {
                selectedModel = first.name
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}