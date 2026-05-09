import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: ChatRecord?

    var body: some View {
        #if os(iOS)
        // NavigationSplitView on iPhone (iOS 17+) presents the sidebar as a
        // sheet over the detail view, leaving a large black gap. NavigationStack
        // gives the expected full-screen list → push behaviour.
        NavigationStack {
            ChatListView(selection: $selection)
                .navigationDestination(item: $selection) { chat in
                    ChatDetailView(chat: chat).id(chat.id)
                }
        }
        .onChange(of: appState.pendingSelection) { _, newChat in
            guard let chat = newChat else { return }
            selection = chat
            appState.pendingSelection = nil
        }
        #else
        NavigationSplitView {
            ChatListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let chat = selection {
                ChatDetailView(chat: chat).id(chat.id)
            } else {
                ChatEmptyDetailView()
            }
        }
        .onChange(of: appState.pendingSelection) { _, newChat in
            guard let chat = newChat else { return }
            selection = chat
            appState.pendingSelection = nil
        }
        #endif
    }
}

private struct ChatEmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 160, height: 160)
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
