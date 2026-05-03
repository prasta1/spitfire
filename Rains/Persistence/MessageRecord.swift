import Foundation
import SwiftData

/// SwiftData persistence record for a single chat message.
///
/// Mirrors the `messages` table in the Flutter app. Image attachments are
/// stored as opaque `Data` here; the binding to the file system is deferred
/// until Phase 6.
///
/// `role` is stored as a `String` (the raw value of `OllamaMessage.Role`)
/// rather than the enum directly because iOS 17/18 SwiftData crashes when
/// persisting raw-representable enums in `@Model`. The `role` computed
/// property hides that detail from callers.
@Model
final class MessageRecord {
    var id: UUID
    var content: String
    var model: String?
    var createdAt: Date
    var imagesData: Data?

    /// Raw value of `OllamaMessage.Role`. Use the `role` computed property.
    /// Not marked `private` because the @Model macro skips private stored
    /// properties, which silently breaks persistence.
    var roleRaw: String

    var chat: ChatRecord?

    init(
        id: UUID = UUID(),
        content: String,
        role: OllamaMessage.Role,
        model: String? = nil,
        createdAt: Date = Date(),
        imagesData: Data? = nil
    ) {
        self.id = id
        self.content = content
        self.model = model
        self.createdAt = createdAt
        self.imagesData = imagesData
        self.roleRaw = role.rawValue
    }
}

extension MessageRecord {
    var role: OllamaMessage.Role {
        get { OllamaMessage.Role(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    static func make(from message: OllamaMessage) -> MessageRecord {
        MessageRecord(
            id: message.id,
            content: message.content,
            role: message.role,
            model: message.model,
            createdAt: message.createdAt
        )
    }

    func toDomain() -> OllamaMessage {
        OllamaMessage(
            id: id,
            content: content,
            role: role,
            createdAt: createdAt,
            model: model
        )
    }
}
