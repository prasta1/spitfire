import SwiftUI

struct MessageBubbleView: View {
    let message: MessageRecord

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: alignment, spacing: 4) {
                Text(message.content.isEmpty ? " " : message.content)
                    .textSelection(.enabled)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(bubbleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if message.role == .system {
                    Text("system")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:      return .accentColor
        case .assistant: return Color(.secondarySystemBackground)
        case .system:    return Color(.tertiarySystemBackground)
        }
    }
}
