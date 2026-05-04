import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var selection: ChatRecord?

    var body: some View {
        NavigationSplitView {
            ChatListView(selection: $selection)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                #endif
        } detail: {
            if let chat = selection {
                ChatDetailView(chat: chat)
                    .id(chat.id)
            } else {
                ChatEmptyDetailView()
            }
        }
    }
}

private struct ChatEmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Select a chat or start a new one")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .modelContainer(try! SpitfireModelContainer.makeInMemory())
}
