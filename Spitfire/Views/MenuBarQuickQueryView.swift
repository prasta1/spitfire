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
        .padding(14)
        .frame(width: 460)
        .task { await loadModels() }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image("MenuBarIcon")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
            Text("Spitfire")
                .font(.headline)
            Spacer()
            if isLoadingModels {
                ProgressView()
                    .controlSize(.small)
            } else if appState.menuBarModel.isEmpty {
                Text("No model available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(appState.menuBarModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var queryInputField: some View {
        TextField("Ask anything…", text: $queryText, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...6)
            .disabled(isStreaming || appState.menuBarModel.isEmpty)
            .onSubmit {
                let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sendQuery() }
            }
    }

    private var responseArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isStreaming && responseText.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            } else {
                ScrollView {
                    renderedResponse
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 300)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// Renders the response as Markdown when possible; falls back to plain text
    /// for incomplete chunks during streaming that fail to parse.
    @ViewBuilder
    private var renderedResponse: some View {
        if let attributed = try? AttributedString(
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
                            || appState.menuBarModel.isEmpty
                    )
            }
        }
    }

    // MARK: - Actions

    private func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await appState.activeClient.listModels()
            // Persist first available if no model is set yet, or if the saved
            // model is no longer in the list (e.g. after a model is deleted).
            let names = models.map(\.name)
            if appState.menuBarModel.isEmpty || !names.contains(appState.menuBarModel),
               let first = models.first {
                appState.menuBarModel = first.name
            }
        } catch {
            // Leave menuBarModel as-is so the last known value survives transient errors.
        }
    }

    private func sendQuery() {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = appState.menuBarModel
        guard !trimmed.isEmpty, !model.isEmpty else { return }

        responseText = ""
        errorMessage = nil
        isStreaming = true
        queryText = ""

        // Persist chat and user message upfront
        let chat = ChatRecord(model: model, title: String(trimmed.prefix(50)))
        modelContext.insert(chat)
        let userMsg = MessageRecord(content: trimmed, role: .user)
        userMsg.chat = chat
        modelContext.insert(userMsg)
        try? modelContext.save()
        currentChat = chat

        let domainChat = chat.toDomain()
        let history = [OllamaMessage(content: trimmed, role: .user)]

        streamTask = Task { @MainActor in
            var accumulated = ""
            do {
                let stream = appState.activeClient.chatStream(messages: history, in: domainChat)
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
                    model: model
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
