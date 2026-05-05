#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

/// Compact popover shown from the macOS menu bar icon.
///
/// Lets the user fire off a quick Ollama query without opening the main window.
/// Every query creates a `ChatRecord` + `MessageRecord`s in SwiftData so the
/// conversation is preserved and accessible via "Open in Spitfire".
struct MenuBarQuickQueryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    @State private var availableModels: [OllamaModel] = []
    @State private var selectedModel: String = ""
    @State private var queryText: String = ""
    @State private var responseText: String = ""
    @State private var isStreaming: Bool = false
    @State private var streamTask: Task<Void, Never>?
    @State private var currentChat: ChatRecord?
    @State private var errorMessage: String?
    @State private var isLoadingModels: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Divider()
            queryInputField
            if !responseText.isEmpty || isStreaming {
                responseArea
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            actionRow
        }
        .padding()
        .frame(width: 360)
        .task { await loadModels() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "airplane.fill")
                .foregroundStyle(.tint)
            Text("Spitfire")
                .font(.headline)
            Spacer()
            if isLoadingModels {
                ProgressView()
                    .controlSize(.small)
            } else if availableModels.isEmpty {
                Text("Ollama not reachable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Model", selection: $selectedModel) {
                    ForEach(availableModels, id: \.name) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 190)
            }
        }
    }

    private var queryInputField: some View {
        TextField("Ask anything…", text: $queryText, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
            .disabled(isStreaming || availableModels.isEmpty)
            .onSubmit {
                let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sendQuery() }
            }
    }

    private var responseArea: some View {
        ScrollView {
            renderedResponse
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.body)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 220)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Renders the response as Markdown when possible; falls back to plain text
    /// for incomplete chunks during streaming that fail to parse.
    @ViewBuilder
    private var renderedResponse: some View {
        if responseText.isEmpty {
            Text("…").foregroundStyle(.secondary)
        } else if let attributed = try? AttributedString(
            markdown: responseText,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) {
            Text(attributed)
        } else {
            Text(responseText)
        }
    }

    private var actionRow: some View {
        HStack {
            if let chat = currentChat, !isStreaming {
                Button("Open in Spitfire") {
                    openInSpitfire(chat: chat)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
            }
            Spacer()
            if isStreaming {
                Button("Stop") { stopStream() }
                    .buttonStyle(.bordered)
            } else {
                Button("Send") { sendQuery() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(
                        queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || selectedModel.isEmpty
                    )
            }
        }
    }

    // MARK: - Actions

    private func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await appState.client.listModels()
            availableModels = models
            if selectedModel.isEmpty, let first = models.first {
                selectedModel = first.name
            }
        } catch {
            availableModels = []
        }
    }

    private func sendQuery() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedModel.isEmpty else { return }

        responseText = ""
        errorMessage = nil
        isStreaming = true
        queryText = ""

        // Persist chat and user message upfront
        let chat = ChatRecord(model: selectedModel, title: String(trimmed.prefix(50)))
        modelContext.insert(chat)
        let userMsg = MessageRecord(content: trimmed, role: .user)
        userMsg.chat = chat
        modelContext.insert(userMsg)
        try? modelContext.save()
        currentChat = chat

        let domainChat = chat.toDomain()
        let history = [OllamaMessage(content: trimmed, role: .user)]

        streamTask = Task {
            var accumulated = ""
            do {
                let stream = appState.client.chatStream(messages: history, in: domainChat)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    accumulated += chunk.content
                    responseText = accumulated
                    if chunk.metadata?.done == true { break }
                }
            } catch is CancellationError {
                // keep accumulated text as-is
            } catch {
                errorMessage = error.localizedDescription
            }

            // Save the assistant reply
            if !accumulated.isEmpty {
                let assistantMsg = MessageRecord(
                    content: accumulated,
                    role: .assistant,
                    model: selectedModel
                )
                assistantMsg.chat = chat
                modelContext.insert(assistantMsg)
                try? modelContext.save()
            }

            isStreaming = false
        }
    }

    private func stopStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    private func openInSpitfire(chat: ChatRecord) {
        appState.pendingSelection = chat
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
