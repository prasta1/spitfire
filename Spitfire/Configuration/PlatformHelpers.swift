import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let openSettings = Notification.Name("spitfire.openSettings")
}

// MARK: - Platform Image

#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - Platform Colors

extension Color {
    static var secondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var tertiaryBackground: Color {
        #if os(iOS)
        Color(.tertiarySystemBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    static var tertiaryFill: Color {
        #if os(iOS)
        Color(.tertiarySystemFill)
        #else
        Color(nsColor: .controlColor)
        #endif
    }
}

// MARK: - Clipboard

enum Clipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies `.navigationBarTitleDisplayMode(.inline)` on iOS, no-op on macOS.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Applies iOS keyboard modifiers, no-op on macOS.
    @ViewBuilder
    func noAutocapitalization() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    /// Applies `.keyboardType(.URL)` on iOS, no-op on macOS.
    @ViewBuilder
    func urlKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.URL)
        #else
        self
        #endif
    }

    /// Semi-transparent list row background matching the frosted card style used on iOS.
    @ViewBuilder
    func frostedRow() -> some View {
        #if os(iOS)
        self.listRowBackground(Color(.systemBackground).opacity(0.55))
        #else
        self
        #endif
    }
}
