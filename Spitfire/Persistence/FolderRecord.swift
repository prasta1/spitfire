import Foundation
import SwiftData

/// SwiftData persistence record for a user-created chat folder.
///
/// Deleting a folder nullifies the `folder` relationship on all member chats —
/// chats are never deleted when their folder is removed.
@Model
final class FolderRecord {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \ChatRecord.folder)
    var chats: [ChatRecord] = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
