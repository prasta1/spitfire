import SwiftData
import SwiftUI

struct ChatConfigurationView: View {
    @Bindable var chat: ChatRecord
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var modelLoadState: ModelLoadState = .loading
    @State private var saveAsName: String = ""
    @State private var saveAsState: SaveAsState = .idle

    enum ModelLoadState: Equatable {
        case loading
        case loaded([OllamaModel])
        case failed
    }

    enum SaveAsState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                titleSection
                modelSection
                systemPromptSection
                optionsSection
                resetSection
                if appState.activeBackend == .ollama {
                    saveAsCustomSection
                }
            }
            .navigationTitle("Configure")
            .inlineNavigationTitle()
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .task { await loadModels() }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 500, idealHeight: 640)
        #endif
    }

    // MARK: Title

    @ViewBuilder
    private var titleSection: some View {
        Section("Title") {
            TextField("Title", text: $chat.title)
        }
    }

    // MARK: Model

    @ViewBuilder
    private var modelSection: some View {
        Section {
            switch modelLoadState {
            case .loading:
                HStack {
                    Text("Loading models…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            case .loaded(let models) where !models.isEmpty:
                Picker("Model", selection: $chat.model) {
                    ForEach(modelChoices(installed: models)) { model in
                        ModelLabel(model: model).tag(model.name)
                    }
                }
            default:
                TextField("Model", text: $chat.model)
            }
        } header: {
            Text("Model")
        } footer: {
            switch modelLoadState {
            case .failed:
                Text("Couldn't reach the server; you can still type a model name.")
            default:
                EmptyView()
            }
        }
    }

    /// Always include the chat's current model so we can show it even if
    /// the user uninstalls it server-side or swapped server URL.
    private func modelChoices(installed: [OllamaModel]) -> [OllamaModel] {
        var models = installed
        if !models.contains(where: { $0.name == chat.model }) {
            models.insert(OllamaModel(
                name: chat.model, model: chat.model,
                modifiedAt: .distantPast, size: 0, digest: chat.model,
                parameterSize: "", capabilities: nil
            ), at: 0)
        }
        return models
    }

    // MARK: System prompt

    @ViewBuilder
    private var systemPromptSection: some View {
        Section {
            TextField(
                "Optional system prompt",
                text: Binding(
                    get: { chat.systemPrompt ?? "" },
                    set: { chat.systemPrompt = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...8)
        } header: {
            Text("System prompt")
        } footer: {
            Text("Prepended to every conversation as a system message.")
        }
    }

    // MARK: Generation options

    @ViewBuilder
    private var optionsSection: some View {
        Section("Generation options") {
            sliderRow("Temperature", value: $chat.optTemperature, in: 0...2, step: 0.05, format: "%.2f")
            sliderRow("Top P", value: $chat.optTopP, in: 0...1, step: 0.01, format: "%.2f")
            sliderRow("Min P", value: $chat.optMinP, in: 0...1, step: 0.01, format: "%.2f")
            stepperRow("Top K", value: $chat.optTopK, in: 1...500, step: 1)
            stepperRow("Context size", value: $chat.optContextSize, in: 256...32_768, step: 256)
            maxTokensRow
            sliderRow("Repeat penalty", value: $chat.optRepeatPenalty, in: 0.5...2, step: 0.05, format: "%.2f")
            stepperRow("Repeat last N", value: $chat.optRepeatLastN, in: -1...4096, step: 1)
            stepperRow("Seed", value: $chat.optSeed, in: 0...Int(Int32.max), step: 1)

            DisclosureGroup("Mirostat") {
                Picker("Mode", selection: $chat.optMirostat) {
                    Text("Off").tag(0)
                    Text("Mirostat 1").tag(1)
                    Text("Mirostat 2").tag(2)
                }
                sliderRow("Eta", value: $chat.optMirostatEta, in: 0...1, step: 0.01, format: "%.2f")
                sliderRow("Tau", value: $chat.optMirostatTau, in: 0...10, step: 0.1, format: "%.1f")
                sliderRow("Tail-free sampling", value: $chat.optTailFreeSampling, in: 0...2, step: 0.05, format: "%.2f")
            }
        }
    }

    @ViewBuilder
    private var maxTokensRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Max tokens")
                Spacer()
                Text(chat.optMaxTokens <= 0 ? "Unlimited" : "\(chat.optMaxTokens)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Toggle("Limit", isOn: Binding(
                    get: { chat.optMaxTokens > 0 },
                    set: { isOn in chat.optMaxTokens = isOn ? max(chat.optMaxTokens, 256) : -1 }
                ))
                .labelsHidden()
                Stepper(value: $chat.optMaxTokens, in: 1...32_768, step: 64) { EmptyView() }
                    .disabled(chat.optMaxTokens <= 0)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                chat.options = OllamaChatOptions()
            } label: {
                Text("Reset options to defaults")
            }
        }
    }

    // MARK: Save as custom model

    @ViewBuilder
    private var saveAsCustomSection: some View {
        Section {
            TextField("New model name", text: $saveAsName)
                .noAutocapitalization()
                .autocorrectionDisabled()

            Button {
                Task { await saveAsCustomModel() }
            } label: {
                HStack {
                    Text("Save as custom model")
                    Spacer()
                    saveAsStatusIcon
                }
            }
            .disabled(!canSaveAsCustom)

            if case .failed(let message) = saveAsState {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Custom model")
        } footer: {
            Text("Creates a new model on the server based on this chat's system prompt and options.")
        }
    }

    @ViewBuilder
    private var saveAsStatusIcon: some View {
        switch saveAsState {
        case .idle: EmptyView()
        case .saving: ProgressView()
        case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var canSaveAsCustom: Bool {
        let trimmed = saveAsName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && saveAsState != .saving
    }

    private func saveAsCustomModel() async {
        let name = saveAsName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        saveAsState = .saving
        do {
            try await appState.client.createModel(name, from: chat.toDomain())
            saveAsState = .saved
            saveAsName = ""
            await loadModels()  // refresh picker so the new model appears
        } catch {
            saveAsState = .failed(error.localizedDescription)
        }
    }

    private func loadModels() async {
        modelLoadState = .loading
        do {
            let models = try await appState.activeClient.listModels()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            modelLoadState = .loaded(models)
        } catch {
            modelLoadState = .failed
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func sliderRow(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    @ViewBuilder
    private func stepperRow(
        _ label: String,
        value: Binding<Int>,
        in range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue)").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
