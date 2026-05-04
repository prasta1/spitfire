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
    @State private var runningModels: [RunningModel] = []
    @State private var unloadingModel: String?
    @State private var pullName: String = ""
    @State private var pullState: PullState = .idle
    @State private var registryModels: [String] = []
    @State private var searchTask: Task<Void, Never>?

    enum PullState: Equatable {
        case idle
        case pulling(String)
        case progress(String, Double)
        case done
        case failed(String)
    }

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

                if !runningModels.isEmpty {
                    loadedModelsSection
                }

                pullModelSection
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
            .task { await loadAll() }
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
                        ModelLabel(
                            model: model,
                            isLoaded: runningNames.contains(model.name)
                        ).tag(model.name)
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

    @ViewBuilder
    private var loadedModelsSection: some View {
        Section {
            ForEach(runningModels) { running in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text(running.name)
                                .lineLimit(1)
                        }
                        Text("\(running.parameterSize) · \(running.quantization) · \(running.formattedVram)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if unloadingModel == running.name {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            Task { await unload(running.name) }
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Loaded in Memory")
        } footer: {
            let totalVram = runningModels.reduce(0) { $0 + $1.sizeVram }
            let gb = Double(totalVram) / 1_073_741_824
            Text(String(format: "%.1f GB VRAM in use", gb))
        }
    }

    // MARK: - Pull Model

    @ViewBuilder
    private var pullModelSection: some View {
        Section {
            TextField("Search or enter model name", text: $pullName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isPulling)
                .onChange(of: pullName) { _, newValue in
                    debounceSearch(query: newValue)
                }

            if !filteredSuggestions.isEmpty && !isPulling {
                suggestionsView
            }

            Button {
                Task { await pullModel() }
            } label: {
                HStack {
                    Text("Pull Model")
                    Spacer()
                    pullStatusView
                }
            }
            .disabled(pullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPulling)

            if case .progress(let status, let fraction) = pullState {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction)
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if case .pulling(let status) = pullState {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = pullState {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Pull New Model")
        } footer: {
            Text("Search the Ollama registry or enter an exact model name.")
        }
    }

    @ViewBuilder
    private var suggestionsView: some View {
        let suggestions = filteredSuggestions
        FlowLayout(spacing: 6) {
            ForEach(suggestions, id: \.self) { name in
                Button {
                    pullName = name
                } label: {
                    Text(name)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var pullStatusView: some View {
        switch pullState {
        case .idle, .failed: EmptyView()
        case .pulling, .progress: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    /// Suggestions filtered by current input, excluding already-installed models.
    private var filteredSuggestions: [String] {
        let installed: Set<String>
        if case .loaded(let models) = loadState {
            installed = Set(models.map(\.name))
        } else {
            installed = []
        }

        let query = pullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return registryModels.filter { name in
            !installed.contains(name) && !installed.contains("\(name):latest")
                && (query.isEmpty || name.localizedCaseInsensitiveContains(query))
        }
    }

    private var isPulling: Bool {
        switch pullState {
        case .pulling, .progress: return true
        default: return false
        }
    }

    private var runningNames: Set<String> {
        Set(runningModels.map(\.name))
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

    // MARK: - Data Loading

    private func loadAll() async {
        async let modelsTask: () = loadModels()
        async let runningTask: () = loadRunning()
        async let registryTask: () = loadRegistry()
        _ = await (modelsTask, runningTask, registryTask)
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

    private func loadRunning() async {
        do {
            runningModels = try await appState.client.listRunning()
        } catch {
            runningModels = []
        }
    }

    private func loadRegistry() async {
        registryModels = await OllamaClient.searchRegistry()
    }

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            // Reset to popular when cleared
            if trimmed.isEmpty {
                searchTask = Task {
                    registryModels = await OllamaClient.searchRegistry()
                }
            }
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            registryModels = await OllamaClient.searchRegistry(query: trimmed)
        }
    }

    private func pullModel() async {
        let name = pullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        pullState = .pulling("Starting…")

        do {
            let stream = appState.client.pullModel(name)
            for try await progress in stream {
                if let fraction = progress.fraction {
                    pullState = .progress(progress.status, fraction)
                } else {
                    pullState = .pulling(progress.status)
                }
            }
            pullState = .done
            pullName = ""
            await loadModels()
        } catch {
            pullState = .failed(error.localizedDescription)
        }
    }

    private func unload(_ name: String) async {
        unloadingModel = name
        do {
            try await appState.client.unloadModel(name)
            runningModels.removeAll { $0.name == name }
        } catch {
            // Silently fail — model may have already been unloaded
        }
        unloadingModel = nil
    }
}

// MARK: - FlowLayout

/// Simple horizontal wrapping layout for suggestion chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
