import SwiftData
import SwiftUI

struct ChatListView: View {
    @Binding var selection: ChatRecord?
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatRecord.createdAt, order: .reverse) private var allChats: [ChatRecord]
    @Query(sort: \FolderRecord.createdAt) private var folders: [FolderRecord]

    @State private var showingNewChat = false
    @State private var showingSettings = false
    @State private var collapsedFolders: Set<UUID> = []
    @State private var activeFolder: FolderRecord? = nil
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderBeingRenamed: FolderRecord? = nil
    @State private var renameFolderName = ""
    @State private var dropTargetFolderID: UUID? = nil
    @State private var dropTargetingUnfiled = false

    private var unfiledChats: [ChatRecord] {
        allChats.filter { $0.folder == nil }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(folders) { folder in
                folderSection(for: folder)
            }

            Button {
                showingNewFolderAlert = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 2)

            Section {
                ForEach(unfiledChats) { chat in
                    chatRow(chat)
                }
                .onDelete { offsets in deleteChats(at: offsets, from: unfiledChats) }
            } header: {
                if !folders.isEmpty {
                    Text("Unfiled")
                        .padding(.vertical, 2)
                        .padding(.horizontal, 4)
                        .background(dropTargetingUnfiled ? Color.accentColor.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .dropDestination(for: String.self) { items, _ in
                            for uuidString in items {
                                guard let id = UUID(uuidString: uuidString),
                                      let chat = allChats.first(where: { $0.id == id }) else { continue }
                                move(chat, to: nil)
                            }
                            return true
                        } isTargeted: { dropTargetingUnfiled = $0 }
                }
            }
        }
        .navigationTitle("Spitfire")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewChat = true } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }
        }
        .overlay {
            if allChats.isEmpty {
                EmptyStateView(onNewChat: { _ in showingNewChat = true })
            }
        }
        .sheet(isPresented: $showingNewChat) {
            NewChatSheet(onCreate: { modelName in
                let chat = ChatRecord(model: modelName)
                chat.folder = activeFolder
                context.insert(chat)
                try? context.save()
                selection = chat
            })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: selection) { _, newVal in
            activeFolder = newVal?.folder
        }
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Name", text: $newFolderName)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { folderBeingRenamed != nil },
            set: { if !$0 { folderBeingRenamed = nil } }
        )) {
            TextField("Name", text: $renameFolderName)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { folderBeingRenamed = nil }
        }
    }

    // MARK: - Folder section

    @ViewBuilder
    private func folderSection(for folder: FolderRecord) -> some View {
        let isCollapsed = collapsedFolders.contains(folder.id)
        let sortedChats = folder.chats.sorted { $0.createdAt > $1.createdAt }

        Section {
            if !isCollapsed {
                ForEach(sortedChats) { chat in
                    chatRow(chat)
                }
                .onDelete { offsets in deleteChats(at: offsets, from: sortedChats) }
            }
        } header: {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleCollapsed(folder)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(folder.name)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button("Rename") {
                        folderBeingRenamed = folder
                        renameFolderName = folder.name
                    }
                    Button("Delete Folder", role: .destructive) {
                        deleteFolder(folder)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background(
                dropTargetFolderID == folder.id
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .dropDestination(for: String.self) { items, _ in
                for uuidString in items {
                    guard let id = UUID(uuidString: uuidString),
                          let chat = allChats.first(where: { $0.id == id }) else { continue }
                    move(chat, to: folder)
                }
                return true
            } isTargeted: { isOver in
                dropTargetFolderID = isOver ? folder.id : nil
            }
        }
    }

    // MARK: - Chat row

    @ViewBuilder
    private func chatRow(_ chat: ChatRecord) -> some View {
        ChatListRow(chat: chat)
            .tag(chat)
            .draggable(chat.id.uuidString)
            .contextMenu {
                if !folders.isEmpty {
                    Menu("Move to…") {
                        ForEach(folders.filter { $0.id != chat.folder?.id }) { folder in
                            Button(folder.name) { move(chat, to: folder) }
                        }
                        if chat.folder != nil {
                            Divider()
                            Button("Remove from folder") { move(chat, to: nil) }
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    if selection?.id == chat.id { selection = nil }
                    context.delete(chat)
                    try? context.save()
                }
            }
    }

    // MARK: - Actions

    private func toggleCollapsed(_ folder: FolderRecord) {
        if collapsedFolders.contains(folder.id) {
            collapsedFolders.remove(folder.id)
        } else {
            collapsedFolders.insert(folder.id)
        }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { newFolderName = "" }
        guard !trimmed.isEmpty else { return }
        let folder = FolderRecord(name: trimmed)
        context.insert(folder)
        try? context.save()
    }

    private func commitRename() {
        let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let folder = folderBeingRenamed else { return }
        folder.name = trimmed
        try? context.save()
        folderBeingRenamed = nil
    }

    private func deleteFolder(_ folder: FolderRecord) {
        if let selected = selection, selected.folder?.id == folder.id {
            selection = nil
        }
        // .nullify delete rule sets chat.folder = nil on all member chats
        context.delete(folder)
        try? context.save()
    }

    private func move(_ chat: ChatRecord, to folder: FolderRecord?) {
        chat.folder = folder
        try? context.save()
    }

    private func deleteChats(at offsets: IndexSet, from chats: [ChatRecord]) {
        for index in offsets {
            let chat = chats[index]
            if selection?.id == chat.id { selection = nil }
            context.delete(chat)
        }
        try? context.save()
    }
}

// MARK: - Chat list row

private struct ChatListRow: View {
    let chat: ChatRecord

    /// OpenRouter model IDs always contain a "/" (e.g. "anthropic/claude-opus-4").
    private var isOpenRouter: Bool { chat.model.contains("/") }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(isOpenRouter ? Color.indigo : Color.teal)
                .frame(width: 7, height: 7)

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
}
