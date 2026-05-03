import PhotosUI
import SwiftData
import SwiftUI

struct ChatDetailView: View {
    @Bindable var chat: ChatRecord
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var viewModel: ChatDetailViewModel?
    @State private var showingConfig = false
    @State private var pickerSelection: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingConfig = true
                } label: {
                    Label("Configure", systemImage: "slider.horizontal.3")
                }
            }
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
        }
    }

    @ViewBuilder
    private var inputBar: some View {
        if let viewModel {
            VStack(spacing: 6) {
                pendingImagePreview(for: viewModel)

                HStack(alignment: .bottom, spacing: 8) {
                    PhotosPicker(selection: $pickerSelection, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                    }
                    .disabled(viewModel.isStreaming)

                    TextField("Message", text: Binding(
                        get: { viewModel.inputText },
                        set: { viewModel.inputText = $0 }
                    ), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .disabled(viewModel.isStreaming)

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
            .onChange(of: pickerSelection) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        viewModel.pendingImage = data
                    }
                    pickerSelection = nil
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for message: MessageRecord) -> some View {
        Button {
            UIPasteboard.general.string = message.content
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
        if let data = viewModel.pendingImage, let uiImage = UIImage(data: data) {
            HStack {
                Image(uiImage: uiImage)
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
}
