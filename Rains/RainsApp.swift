import SwiftData
import SwiftUI

@main
struct RainsApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try RainsModelContainer.makeShared()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.ollamaClient, OllamaClient(baseURL: AppConfiguration.serverURL))
        }
        .modelContainer(modelContainer)
    }
}
