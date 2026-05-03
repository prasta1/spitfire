import SwiftUI

struct TypingIndicatorView: View {
    @State private var isAnimating = false
    
    private let dots = [0, 1, 2]
    
    var body: some View {
        HStack(spacing: 5) {
            ForEach(dots, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating && currentDot == index ? 1.2 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .onAppear {
            isAnimating = true
        }
    }
    
    private var currentDot: Int {
        Int(Date().timeIntervalSince1970 * 1000) / 400 % 3
    }
}

#Preview {
    TypingIndicatorView()
}