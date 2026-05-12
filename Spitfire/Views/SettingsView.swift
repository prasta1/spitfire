import Darwin
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String = ""
    @State private var lmStudioURLInput: String = ""
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
    @State private var quickConnectHost: String = ""
    @State private var isQuickConnecting: Bool = false
    @State private var scanState: ScanState = .idle
    @State private var discoveredServers: [URL] = []

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

    enum ScanState: Equatable { case idle, scanning, done }

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
                backendSection
                connectionSection
                appearanceSection
                modelsSection
            }
            .navigationTitle("Settings")
            .inlineNavigationTitle()
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        commitURL()
                        commitLMStudioURL()
                        dismiss()
                    }
                }
            }
            .onAppear {
                urlInput = appState.serverURL.absoluteString
                lmStudioURLInput = appState.lmStudioURL.absoluteString
            }
            .task { await loadModels() }
            .onChange(of: appState.activeBackend) { _, _ in Task { await loadModels() } }
            .onChange(of: appState.serverURL) { _, _ in Task { await loadModels() } }
            .onChange(of: appState.lmStudioURL) { _, _ in Task { await loadModels() } }
        }
        #if os(iOS)
        .presentationBackground {
            ZStack {
                Image("LaunchBackground")
                    .resizable()
                    .scaledToFill()
                Color.black.opacity(0.25)
            }
            .ignoresSafeArea()
        }
        #endif
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 460, idealHeight: 480)
        #endif
    }

    // MARK: - Backend + connection sections

    @ViewBuilder
    private var backendSection: some View {
        @Bindable var bindable = appState

        Section("Backend") {
            Picker("Provider", selection: $bindable.activeBackend) {
                ForEach(ActiveBackend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .frostedRow()
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        switch appState.activeBackend {
        case .ollama:
            serverSection
            discoverSection
        case .lmStudio:
            lmStudioSection
        case .openRouter:
            openRouterSection
        }
    }

    // MARK: - Per-backend config sections

    @ViewBuilder
    private var discoverSection: some View {
        Section {
            HStack {
                TextField("Hostname or IP", text: $quickConnectHost)
                    .noAutocapitalization()
                    .autocorrectionDisabled()
                    .onSubmit { Task { await tryQuickConnect() } }
                if isQuickConnecting { ProgressView().controlSize(.small) }
                Button("Connect") { Task { await tryQuickConnect() } }
                    .disabled(quickConnectHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isQuickConnecting)
            }
            .frostedRow()

            Button {
                Task { await scanLocalNetwork() }
            } label: {
                HStack {
                    Text("Scan local network")
                    Spacer()
                    if scanState == .scanning { ProgressView().controlSize(.small) }
                }
            }
            .disabled(scanState == .scanning)
            .frostedRow()

            if !discoveredServers.isEmpty {
                ForEach(discoveredServers, id: \.self) { url in
                    Button {
                        appState.serverURL = url
                        connectionState = .idle
                    } label: {
                        Label(url.host() ?? url.absoluteString, systemImage: "server.rack")
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .frostedRow()
                }
            } else if scanState == .done {
                Text("No Ollama servers found on this network.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frostedRow()
            }
        } header: {
            Text("Discover")
        } footer: {
            Text("Enter a Tailscale hostname, a .local name, or an IP. Or scan your local network for Ollama instances.")
        }
    }

    @ViewBuilder
    private var lmStudioSection: some View {
        Section {
            TextField(text: $lmStudioURLInput, prompt: Text("http://localhost:1234")) {
                Text("Server URL")
            }
            .noAutocapitalization()
            .autocorrectionDisabled()
            .urlKeyboard()
            .onSubmit { commitLMStudioURL() }
            .frostedRow()
        } header: {
            Text("LM Studio")
        } footer: {
            Text("Base URL of your LM Studio local server. Default: http://localhost:1234")
        }
    }

    @ViewBuilder
    private var openRouterSection: some View {
        @Bindable var bindable = appState

        Section("OpenRouter") {
            SecureField("API Key", text: $bindable.openRouterAPIKey)
                .noAutocapitalization()
                .autocorrectionDisabled()
                .truncationMode(.middle)
                .frostedRow()
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
            .frostedRow()

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
            .frostedRow()

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
            .frostedRow()
            Stepper(
                "Font Size (\(Int(bindable.messageFontSize))pt)",
                value: $bindable.messageFontSize,
                in: 11...24,
                step: 1
            )
            .frostedRow()
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
                .frostedRow()
            case .loaded(let models):
                if models.isEmpty {
                    let emptyText: String = {
                        switch appState.activeBackend {
                        case .openRouter: return "No models available"
                        case .lmStudio: return "No models loaded in LM Studio"
                        case .ollama: return "No models installed on the server"
                        }
                    }()
                    Text(emptyText)
                        .foregroundStyle(.secondary)
                        .frostedRow()
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
                        .frostedRow()
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frostedRow()
            }
        } header: {
            let headerText: String = {
                switch appState.activeBackend {
                case .openRouter: return "Available Models"
                case .lmStudio: return "Loaded Models"
                case .ollama: return "Installed Models"
                }
            }()
            Text(headerText)
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
                    .frostedRow()
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
                .frostedRow()

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
                .frostedRow()

                if case .progress(let status, let fraction) = pullState {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: fraction)
                        Text(status).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frostedRow()
                } else if case .pulling(let status) = pullState {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    .frostedRow()
                }

                if case .failed(let message) = pullState {
                    Text(message).font(.footnote).foregroundStyle(.red)
                        .frostedRow()
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
                        .frostedRow()
                }
            }
            .frostedRow()
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

    // MARK: - Discovery

    private func tryQuickConnect() async {
        let host = quickConnectHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        isQuickConnecting = true
        defer { isQuickConnecting = false }

        let candidates: [URL]
        if host.contains("://") {
            candidates = [URL(string: host)].compactMap { $0 }
        } else {
            candidates = [
                URL(string: "http://\(host):11434"),
                URL(string: "http://\(host).local:11434"),
                URL(string: "https://\(host):11434")
            ].compactMap { $0 }
        }

        for url in candidates {
            if let found = await Self.probeOllama(url) {
                appState.serverURL = found
                connectionState = .idle
                return
            }
        }
        connectionState = .failure("Could not reach Ollama at \"\(host)\"")
    }

    private func scanLocalNetwork() async {
        scanState = .scanning
        discoveredServers = []

        var candidates: [URL] = [
            URL(string: "http://localhost:11434"),
            URL(string: "http://127.0.0.1:11434")
        ].compactMap { $0 }

        for subnet in localSubnets() {
            for host in 1...254 {
                if let url = URL(string: "http://\(subnet).\(host):11434") {
                    candidates.append(url)
                }
            }
        }

        var found: [URL] = []
        await withTaskGroup(of: URL?.self) { group in
            for url in candidates {
                group.addTask { await Self.probeOllama(url) }
            }
            for await result in group {
                if let url = result { found.append(url) }
            }
        }

        discoveredServers = found
        scanState = .done
    }

    private static func probeOllama(_ url: URL) async -> URL? {
        var req = URLRequest(url: url.appending(path: "api/version"))
        req.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 200 { return url }
        } catch {}
        return nil
    }

    private func localSubnets() -> Set<String> {
        var subnets = Set<String>()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return subnets }
        defer { freeifaddrs(first) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = ptr {
            let addr = iface.pointee.ifa_addr
            if addr?.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                    let parts = ip.split(separator: ".").map(String.init)
                    if parts.count == 4 {
                        subnets.insert("\(parts[0]).\(parts[1]).\(parts[2])")
                    }
                }
            }
            ptr = iface.pointee.ifa_next
        }
        return subnets
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

    private func commitLMStudioURL() {
        let trimmed = lmStudioURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return }
        if url != appState.lmStudioURL {
            appState.lmStudioURL = url
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
