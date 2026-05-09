import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var connectionState: ConnectionState = .idle

    // Model management
    @State private var modelLoadState: ModelLoadState = .loading
    @State private var runningModels: [RunningModel] = []
    @State private var unloadingModel: String?
    @State private var deletingModel: String?
    @State private var pullName: String = ""
    @State private var pullState: PullState = .idle
    @State private var registryModels: [RegistryModel] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var expandedModel: String?

    enum ConnectionState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    enum ModelLoadState: Equatable {
        case loading
        case loaded([OllamaModel])
        case failed(String)
    }

    enum PullState: Equatable {
        case idle
        case pulling(String)
        case progress(String, Double)
        case done
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                openRouterSection
                appearanceSection
                modelsSection
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitURL()
                        dismiss()
                    }
                }
            }
            .onAppear { urlInput = appState.serverURL.absoluteString }
            .task { await loadModels() }
            .onChange(of: appState.activeBackend) { _, _ in Task { await loadModels() } }
            .onChange(of: appState.serverURL) { _, _ in Task { await loadModels() } }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 460, idealHeight: 480)
        #endif
    }

    // MARK: - Existing sections

    @ViewBuilder
    private var openRouterSection: some View {
        @Bindable var bindable = appState

        Section("OpenRouter") {
            SecureField("API Key", text: $bindable.openRouterAPIKey)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        @Bindable var bindable = appState

        Section {
            TextField(text: $urlInput, prompt: Text("http://localhost:11434")) {
                Text("Server URL")
            }
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

    // MARK: - Models section

    @ViewBuilder
    private var modelsSection: some View {
        Section {
            switch modelLoadState {
            case .loading:
                HStack {
                    Text("Loading models…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            case .loaded(let models):
                if models.isEmpty {
                    Text(appState.activeBackend == .openRouter ? "No models available" : "No models installed on the server")
                        .foregroundStyle(.secondary)
                } else {
                    let sorted = models.sorted { a, b in
                        let aFav = appState.isFavorite(a.name)
                        let bFav = appState.isFavorite(b.name)
                        if aFav != bFav { return aFav }
                        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }
                    ForEach(sorted) { model in
                        HStack {
                            ModelLabel(
                                model: model,
                                isLoaded: runningNames.contains(model.name),
                                isFavorite: appState.isFavorite(model.name)
                            )
                            Spacer()
                            Button {
                                appState.toggleFavorite(model.name)
                            } label: {
                                Image(systemName: appState.isFavorite(model.name) ? "star.fill" : "star")
                                    .foregroundStyle(appState.isFavorite(model.name) ? .yellow : .secondary)
                            }
                            .buttonStyle(.borderless)
                            if appState.activeBackend == .ollama {
                                if deletingModel == model.name {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Button {
                                        Task { await deleteModel(model.name) }
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Installed Models")
        }

        if appState.activeBackend == .ollama && !runningModels.isEmpty {
            Section {
                ForEach(runningModels) { running in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Circle().fill(.green).frame(width: 6, height: 6)
                                Text(running.name).lineLimit(1)
                            }
                            Text("\(running.parameterSize) · \(running.quantization) · \(running.formattedVram)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if unloadingModel == running.name {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                Task { await unload(running.name) }
                            } label: {
                                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
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

        if appState.activeBackend == .ollama {
            Section {
                HStack {
                    TextField("Search or enter model name", text: $pullName)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                        .disabled(isPulling)
                        .onChange(of: pullName) { _, newValue in debounceSearch(query: newValue) }
                    if !pullName.isEmpty && !isPulling {
                        Button { pullName = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !groupedSuggestions.isEmpty && !isPulling {
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
                        Text(status).font(.caption2).foregroundStyle(.tertiary)
                    }
                } else if case .pulling(let status) = pullState {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if case .failed(let message) = pullState {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Pull New Model")
            } footer: {
                Text("Search the Ollama registry or enter an exact model name.")
            }
        }
    }

    @ViewBuilder
    private var suggestionsView: some View {
        ForEach(groupedSuggestions, id: \.family) { group in
            DisclosureGroup(group.family) {
                ForEach(group.models) { model in
                    modelSuggestionRow(model)
                }
            }
        }
    }

    @ViewBuilder
    private func modelSuggestionRow(_ model: RegistryModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if model.sizes.count > 1 {
                    withAnimation { expandedModel = expandedModel == model.name ? nil : model.name }
                } else {
                    pullName = model.sizes.isEmpty ? model.name : "\(model.name):\(model.sizes[0])"
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(model.name).font(.subheadline).fontWeight(.medium)
                        ForEach(model.badgeSymbols, id: \.symbol) { badge in
                            Image(systemName: badge.symbol).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.sizes.count > 1 {
                            Image(systemName: expandedModel == model.name ? "chevron.up" : "chevron.down")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if !model.description.isEmpty {
                        Text(model.description).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            if expandedModel == model.name {
                FlowLayout(spacing: 6) {
                    ForEach(model.sizes, id: \.self) { size in
                        Button {
                            pullName = "\(model.name):\(size)"
                            expandedModel = nil
                        } label: {
                            Text(size.uppercased())
                                .font(.caption).fontWeight(.medium)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.tertiaryFill)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
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

    // MARK: - Helpers

    private struct ModelGroup {
        let family: String
        let models: [RegistryModel]
    }

    private var runningNames: Set<String> { Set(runningModels.map(\.name)) }

    private var isPulling: Bool {
        switch pullState {
        case .pulling, .progress: return true
        default: return false
        }
    }

    private var groupedSuggestions: [ModelGroup] {
        var familyOrder: [String] = []
        var familyMap: [String: [RegistryModel]] = [:]
        for model in filteredSuggestions {
            let fam = model.family
            if familyMap[fam] == nil { familyOrder.append(fam) }
            familyMap[fam, default: []].append(model)
        }
        return familyOrder.map { ModelGroup(family: $0, models: familyMap[$0]!) }
    }

    private var filteredSuggestions: [RegistryModel] {
        let installed: Set<String>
        if case .loaded(let models) = modelLoadState {
            installed = Set(models.map(\.name))
        } else {
            installed = []
        }
        let query = pullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return registryModels.filter { model in
            !installed.contains(model.name) && !installed.contains("\(model.name):latest")
                && (query.isEmpty || model.name.localizedCaseInsensitiveContains(query))
        }
    }

    // MARK: - Async actions

    private func loadModels() async {
        modelLoadState = .loading
        do {
            let models = try await appState.activeClient.listModels()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            modelLoadState = .loaded(models)
        } catch {
            modelLoadState = .failed(error.localizedDescription)
        }
        guard appState.activeBackend == .ollama else { return }
        async let runningTask: () = loadRunning()
        async let registryTask: () = loadRegistry()
        _ = await (runningTask, registryTask)
    }

    private func loadRunning() async {
        do { runningModels = try await appState.client.listRunning() }
        catch { runningModels = [] }
    }

    private func loadRegistry() async {
        registryModels = await OllamaClient.searchRegistry()
    }

    private func deleteModel(_ name: String) async {
        deletingModel = name
        do {
            try await appState.client.deleteModel(name)
            if case .loaded(let models) = modelLoadState {
                modelLoadState = .loaded(models.filter { $0.name != name })
            }
        } catch {}
        deletingModel = nil
    }

    private func unload(_ name: String) async {
        unloadingModel = name
        do {
            try await appState.client.unloadModel(name)
            runningModels.removeAll { $0.name == name }
        } catch {}
        unloadingModel = nil
    }

    private func pullModel() async {
        let name = pullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        pullState = .pulling("Starting…")
        do {
            for try await progress in appState.client.pullModel(name) {
                if let fraction = progress.fraction {
                    pullState = .progress(progress.status, fraction)
                } else {
                    pullState = .pulling(progress.status)
                }
            }
            pullState = .done
            pullName = ""
            await loadModels()
        } catch let error as OllamaError {
            if case .http(_, let body) = error,
               let body, body.contains("file does not exist") || body.contains("not found") {
                pullState = .failed("Model \"\(name)\" not found. Verify the exact name at ollama.com/library.")
            } else {
                pullState = .failed(error.localizedDescription)
            }
        } catch {
            pullState = .failed(error.localizedDescription)
        }
    }

    private func debounceSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            if trimmed.isEmpty {
                searchTask = Task { registryModels = await OllamaClient.searchRegistry() }
            }
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            registryModels = await OllamaClient.searchRegistry(query: trimmed)
        }
    }

    // MARK: - Server

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
