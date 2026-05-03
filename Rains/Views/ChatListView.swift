import SwiftData
import SwiftUI

struct ChatListView: View {
    @Binding var selection: ChatRecord?
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatRecord.createdAt, order: .reverse) private var chats: [ChatRecord]

    @State private var showingNewChat = false
    @State private var showingSettings = false

    var body: some View {
        List(selection: $selection) {
            ForEach(chats) { chat in
                ChatListRow(chat: chat).tag(chat)
            }
            .onDelete(perform: deleteChats)
        }
        .navigationTitle("Spitfire")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewChat = true
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .overlay {
            if chats.isEmpty {
                EmptyStateView(onNewChat: { _ in showingNewChat = true })
            }
        }
        .sheet(isPresented: $showingNewChat) {
            NewChatSheet(onCreate: { modelName in
                let chat = ChatRecord(model: modelName)
                context.insert(chat)
                try? context.save()
                selection = chat
            })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    private func deleteChats(at offsets: IndexSet) {
        for index in offsets {
            let chat = chats[index]
            if selection?.id == chat.id {
                selection = nil
            }
            context.delete(chat)
        }
        try? context.save()
    }
}

private struct ChatListRow: View {
    let chat: ChatRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(chat.title)
                .lineLimit(1)
            Text(chat.model)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
