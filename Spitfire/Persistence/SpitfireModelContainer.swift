import Foundation
import SwiftData

/// Centralized factory for the app's SwiftData container so the app entry
/// and tests build it the same way.
enum SpitfireModelContainer {
    static let schemaTypes: [any PersistentModel.Type] = [
        ChatRecord.self,
        MessageRecord.self,
    ]

    static func makeShared() throws -> ModelContainer {
        // CloudKit sync enabled once iCloud container is fully provisioned.
        // To enable: ModelConfiguration(cloudKitDatabase: .private("iCloud.dev.prasta1.Spitfire"))
        let config = ModelConfiguration()
        do {
            return try ModelContainer(for: Schema(schemaTypes), configurations: config)
        } catch {
            #if DEBUG
            // Store is corrupted (e.g. from a failed CloudKit migration during development).
            // Delete and recreate — data loss is acceptable in debug builds.
            try? FileManager.default.removeItem(at: config.url)
            return try ModelContainer(for: Schema(schemaTypes), configurations: config)
            #else
            throw error
            #endif
        }
    }

    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Schema(schemaTypes), configurations: config)
    }
}
