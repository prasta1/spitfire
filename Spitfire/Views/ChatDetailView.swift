#if os(iOS)
import PhotosUI
#endif
import SwiftData
import SwiftUI

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
    #if os(iOS)
    @State private var pickerSelection: PhotosPickerItem?
    #endif
    #if os(macOS)
    @State private var showingFileImporter = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(chat.title)
        .inlineNavigationTitle()
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                configButton
            }
            #else
            ToolbarItem(placement: .automatic) {
                configButton
            }
            #endif
        }
        .sheet(isPresented: $showingConfig) {
            ChatConfigurationView(chat: chat)
        }
        .onAppear {
            if viewModel == nil {
                viewModel = ChatDetailViewModel(chat: chat, context: context, client: appState.client)
            }
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

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
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
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    jumpToBottomButton(proxy: proxy)
                }
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
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 36, height: 36)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
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
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(viewModel.isStreaming)
                        .onSubmit {
                            if canSend(viewModel) && !viewModel.isStreaming {
                                viewModel.send()
                            }
                        }

                    Button {
                        if viewModel.isStreaming {
                            viewModel.cancel()
                        } else {
                            viewModel.send()
                        }
                    } label: {
                        Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                    .disabled(!viewModel.isStreaming && !canSend(viewModel))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
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
                .font(.system(size: 22))
        }
        .disabled(viewModel.isStreaming)
        #else
        Button {
            showingFileImporter = true
        } label: {
            Image(systemName: "photo")
                .font(.system(size: 22))
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

        if message.role == .assistant,
           message.id == chat.orderedMessages.last(where: { $0.role == .assistant })?.id,
           let viewModel,
           !viewModel.isStreaming {
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
