#if os(iOS)
import PhotosUI
#endif
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - TextDocument (for fileExporter)

/// A minimal FileDocument wrapper that exports a plain-text string.
struct TextDocument: FileDocument {
    /// macOS 12+ knows markdown natively; fall back to plain text if not available.
    static let markdownType: UTType = UTType(filenameExtension: "md") ?? .plainText
    static var readableContentTypes: [UTType] { [.plainText, markdownType] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChatDetailView: View {
    @Bindable var chat: ChatRecord
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var viewModel: ChatDetailViewModel?
    @State private var showingConfig = false
    @State private var isAtBottom: Bool = true
    @State private var scrollOffset: CGFloat = 0
    @State private var exportingMarkdown = false
    @State private var exportingPlainText = false
    @FocusState private var inputFocused: Bool
    #if os(iOS)
    @State private var pickerSelection: PhotosPickerItem?
    #endif
    #if os(macOS)
    @State private var showingFileImporter = false
    #endif

    var body: some View {
        messageList
        .overlay(alignment: .bottom) {
            inputBar
        }
        .background {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.07))
                    .frame(width: 400, height: 400)
                    .blur(radius: 90)
                    .offset(x: 120, y: -140)
                Circle()
                    .fill(Color.cyan.opacity(0.04))
                    .frame(width: 500, height: 500)
                    .blur(radius: 110)
                    .offset(x: -100, y: 180)
            }
            .allowsHitTesting(false)
        }
        .navigationTitle(chat.title)
        .inlineNavigationTitle()
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                exportMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                configButton
            }
            #else
            ToolbarItem(placement: .automatic) {
                exportMenu
            }
            ToolbarItem(placement: .automatic) {
                configButton
            }
            #endif
        }
        .sheet(isPresented: $showingConfig) {
            ChatConfigurationView(chat: chat)
        }
        .fileExporter(
            isPresented: $exportingMarkdown,
            document: TextDocument(text: chat.markdownTranscript),
            contentType: TextDocument.markdownType,
            defaultFilename: "\(chat.title).md"
        ) { _ in }
        .fileExporter(
            isPresented: $exportingPlainText,
            document: TextDocument(text: chat.plainTextTranscript),
            contentType: .plainText,
            defaultFilename: "\(chat.title).txt"
        ) { _ in }
        .onAppear {
            if viewModel == nil {
                viewModel = ChatDetailViewModel(chat: chat, context: context, client: appState.activeClient)
            }
            #if os(iOS)
            if chat.orderedMessages.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    inputFocused = true
                }
            }
            #endif
        }
        .onDisappear { viewModel?.cancel() }
    }

    private var configButton: some View {
        Button {
            showingConfig = true
        } label: {
            Label("Configure", systemImage: "slider.horizontal.3")
        }
    }

    private var exportMenu: some View {
        Menu {
            ShareLink("Share Transcript", item: chat.markdownTranscript)
            Divider()
            Button("Export as Markdown…") { exportingMarkdown = true }
            Button("Export as Plain Text…") { exportingPlainText = true }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chat.orderedMessages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                                .contextMenu { contextMenu(for: message) }
                        }
                        if let viewModel, viewModel.isStreaming {
                            TypingIndicatorView()
                                .id("typing")
                        }
                        if let error = viewModel?.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                    })
                }
                .coordinateSpace(name: "scroll")
                #if os(iOS)
                .contentMargins(.bottom, 100, for: .scrollContent)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    // Force button visible for now on macOS until scroll detection works
                    #if os(macOS)
                    isAtBottom = false
                    #else
                    isAtBottom = value >= -10
                    #endif
                }
                .onChange(of: chat.orderedMessages.last?.content) { _, _ in
                    guard let id = chat.orderedMessages.last?.id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
                .onChange(of: viewModel?.isStreaming) { _, isStreaming in
                    if isStreaming == true {
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }
                .overlay {
                    if chat.orderedMessages.isEmpty {
                        emptyConversationView
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        jumpToBottomButton(proxy: proxy)
                            .padding(.bottom, 72)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.25), value: isAtBottom)
                .animation(.easeOut(duration: 0.2), value: chat.orderedMessages.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func jumpToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                if let id = chat.orderedMessages.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .semibold))
                Text("Latest")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: Color.accentColor.opacity(0.1), radius: 8)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var emptyConversationView: some View {
        let isOpenRouter = chat.model.contains("/")
        let displayName = isOpenRouter
            ? (chat.model.components(separatedBy: "/").last ?? chat.model)
            : chat.model

        VStack(spacing: 12) {
            Circle()
                .fill(isOpenRouter ? Color.indigo.opacity(0.15) : Color.teal.opacity(0.15))
                .frame(width: 56, height: 56)
                .overlay {
                    Circle()
                        .fill(isOpenRouter ? Color.indigo : Color.teal)
                        .frame(width: 10, height: 10)
                }
            Text(displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var inputBar: some View {
        if let viewModel {
            VStack(spacing: 6) {
                pendingImagePreview(for: viewModel)

                HStack(alignment: .center, spacing: 8) {
                    imageAttachButton(for: viewModel)

                    TextField("Message", text: Binding(
                        get: { viewModel.inputText },
                        set: { viewModel.inputText = $0 }
                    ), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .disabled(viewModel.isStreaming)
                        #if os(macOS)
                        .onSubmit {
                            if canSend(viewModel) && !viewModel.isStreaming {
                                viewModel.send()
                            }
                        }
                        #endif

                    Button {
                        if viewModel.isStreaming {
                            viewModel.cancel()
                        } else {
                            viewModel.send()
                            #if os(iOS)
                            inputFocused = true
                            #endif
                        }
                    } label: {
                        Image(systemName: viewModel.isStreaming ? "stop.fill" : "paperplane.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(canSend(viewModel) || viewModel.isStreaming ? Color.accentColor : Color.secondary.opacity(0.3))
                    }
                    .disabled(!viewModel.isStreaming && !canSend(viewModel))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 26))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .accentColor.opacity(0.1), radius: 16, x: 0, y: 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(.clear)
            #if os(iOS)
            .onChange(of: pickerSelection) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        viewModel.pendingImage = data
                    }
                    pickerSelection = nil
                }
            }
            #endif
            #if os(macOS)
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result,
                   url.startAccessingSecurityScopedResource(),
                   let data = try? Data(contentsOf: url) {
                    viewModel.pendingImage = data
                    url.stopAccessingSecurityScopedResource()
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func imageAttachButton(for viewModel: ChatDetailViewModel) -> some View {
        #if os(iOS)
        PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
            Image(systemName: "photo")
                .font(.system(size: 17))
        }
        .disabled(viewModel.isStreaming)
        #else
        Button {
            showingFileImporter = true
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 17))
        }
        .disabled(viewModel.isStreaming)
        #endif
    }

    @ViewBuilder
    private func contextMenu(for message: MessageRecord) -> some View {
        Button {
            Clipboard.copy(message.content)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
            Clipboard.copy(message.plainContent)
        } label: {
            Label("Copy as Plain Text", systemImage: "doc.plaintext")
        }

        ShareLink("Share", item: message.content)

        if message.role == .assistant,
           message.id == chat.orderedMessages.last(where: { $0.role == .assistant })?.id,
           let viewModel,
           !viewModel.isStreaming {
            Divider()
            Button {
                viewModel.regenerateLastAssistant()
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
    }

    private func canSend(_ viewModel: ChatDetailViewModel) -> Bool {
        let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || viewModel.pendingImage != nil
    }

    @ViewBuilder
    private func pendingImagePreview(for viewModel: ChatDetailViewModel) -> some View {
        if let data = viewModel.pendingImage, let platformImage = PlatformImage(data: data) {
            HStack {
                platformImageView(platformImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .clipped()
                Spacer()
                Button {
                    viewModel.pendingImage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func platformImageView(_ image: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: image)
        #else
        Image(nsImage: image)
        #endif
    }
}
