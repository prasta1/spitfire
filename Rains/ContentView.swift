import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.rain")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Rains")
                .font(.largeTitle.bold())
            Text("Phase 0 — bootstrap")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
