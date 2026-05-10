import SwiftUI

struct MessageBubbleView: View {
    let message: MessageRecord

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: alignment, spacing: 4) {
                roleLabel

                if let imageData = message.imagesData,
                   let platformImage = PlatformImage(data: imageData) {
                    image(from: platformImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }

                if !message.content.isEmpty {
                    Text(renderedContent)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(nodeDotColor.opacity(0.1))
                        .background(.ultraThinMaterial)
                        .clipShape(bubbleShape)
                        .overlay { bubbleShape.stroke(nodeDotColor.opacity(0.25), lineWidth: 1) }
                        .shadow(color: nodeDotColor.opacity(0.1), radius: 14, x: 0, y: 4)
                        .overlay(alignment: message.role == .user ? .topTrailing : .topLeading) {
                            Circle()
                                .fill(nodeDotColor)
                                .frame(width: 8, height: 8)
                                .shadow(color: nodeDotColor, radius: 5)
                                .offset(
                                    x: message.role == .user ? 4 : -4,
                                    y: -4
                                )
                        }
                }

                if message.role == .assistant, let stats = message.statsText {
                    Text(stats)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if message.role == .system {
                    Text("system")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var roleLabel: some View {
        switch message.role {
        case .user:
            Text("You")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.0)
        case .assistant:
            Text("Spitfire")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.cyan.opacity(0.7))
                .textCase(.uppercase)
                .tracking(1.0)
        case .system:
            EmptyView()
        }
    }

    private var bubbleShape: AnyShape {
        switch message.role {
        case .user:
            AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: 22, bottomLeadingRadius: 22,
                bottomTrailingRadius: 22, topTrailingRadius: 5
            ))
        case .assistant:
            AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: 5, bottomLeadingRadius: 22,
                bottomTrailingRadius: 22, topTrailingRadius: 22
            ))
        case .system:
            AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var nodeDotColor: Color {
        switch message.role {
        case .user:      return .accentColor
        case .assistant: return .cyan
        case .system:    return .secondary
        }
    }

    /// Inline-only markdown so we get **bold**, *italic*, `code`, and links
    /// without breaking on multi-paragraph content.
    private var renderedContent: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: message.content, options: options) {
            return parsed
        }
        return AttributedString(message.content)
    }

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private func image(from platformImage: PlatformImage) -> Image {
        #if os(iOS)
        Image(uiImage: platformImage)
        #else
        Image(nsImage: platformImage)
        #endif
    }
}
