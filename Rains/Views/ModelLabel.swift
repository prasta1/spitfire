import SwiftUI

/// Lightweight inline label showing a model name with tiny capability icons.
struct ModelLabel: View {
    let model: OllamaModel

    var body: some View {
        HStack(spacing: 4) {
            Text(model.name)
            if let badges = model.capabilities?.badgeSymbols, !badges.isEmpty {
                ForEach(badges, id: \.symbol) { badge in
                    Image(systemName: badge.symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help(badge.label)
                }
            }
        }
    }
}
