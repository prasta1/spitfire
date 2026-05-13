import SwiftUI

struct MessageBubbleView: View {
    let message: MessageRecord
    var onRegenerate: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @Environment(AppState.self) private var appState
    #if os(macOS)
    @State private var isHovered = false
    #endif

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
                        .font(.system(size: appState.messageFontSize))
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

                #if os(macOS)
                if message.role == .assistant {
                    actionBar
                        .opacity(isHovered ? 1 : 0)
                        .allowsHitTesting(isHovered)
                }
                #endif
            }
            #if os(macOS)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            #endif

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

    #if os(macOS)
    private var actionBar: some View {
        HStack(spacing: 14) {
            actionButton("doc.on.doc", tooltip: "Copy") {
                Clipboard.copy(message.content)
            }
            actionButton("doc.plaintext", tooltip: "Copy as Plain Text") {
                Clipboard.copy(message.plainContent)
            }
            if let onRegenerate {
                actionButton("arrow.clockwise", tooltip: "Regenerate", action: onRegenerate)
            }
            if let onDelete {
                actionButton("trash", tooltip: "Delete", tint: .red.opacity(0.7), action: onDelete)
            }
        }
        .padding(.top, 2)
    }

    private func actionButton(
        _ symbol: String,
        tooltip: String,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
    #endif
}
