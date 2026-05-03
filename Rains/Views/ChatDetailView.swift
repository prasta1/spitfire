import SwiftData
import SwiftUI

struct ChatDetailView: View {
    @Bindable var chat: ChatRecord
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var viewModel: ChatDetailViewModel?

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    @ViewBuilder
    private var inputBar: some View {
        if let viewModel {
            HStack(alignment: .bottom, spacing: 8) {
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
                .disabled(!viewModel.isStreaming && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
