import SwiftUI

struct EmptyStateView: View {
    let onNewChat: (String) -> Void
    
    private let suggestions = [
        "Explain quantum computing simply",
        "Help me write a poem",
        "Debug this code for me",
        "What is the meaning of life?"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("No chats yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Start a conversation or try a suggestion below")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onNewChat(suggestion)
                    } label: {
                        Text("Try: \"\(suggestion)\"")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.secondaryBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Button {
                onNewChat("")
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("Start new chat")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

#Preview {
    EmptyStateView(onNewChat: { _ in })
}