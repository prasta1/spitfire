import SwiftUI

private struct OllamaClientKey: EnvironmentKey {
    static let defaultValue: OllamaClient = OllamaClient()
}

extension EnvironmentValues {
    var ollamaClient: OllamaClient {
        get { self[OllamaClientKey.self] }
        set { self[OllamaClientKey.self] = newValue }
    }
}
