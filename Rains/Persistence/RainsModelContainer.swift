import Foundation
import SwiftData

/// Centralized factory for the app's SwiftData container so the app entry
/// and tests build it the same way.
enum RainsModelContainer {
    static let schemaTypes: [any PersistentModel.Type] = [
        ChatRecord.self,
        MessageRecord.self,
    ]

    static func makeShared() throws -> ModelContainer {
        try ModelContainer(for: Schema(schemaTypes), configurations: ModelConfiguration())
    }

    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(schemaTypes), configurations: config)
    }
}
