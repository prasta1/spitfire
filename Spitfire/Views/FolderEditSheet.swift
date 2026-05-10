import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI

struct FolderEditSheet: View {
    enum Mode {
        case create
        case rename(FolderRecord)

        var title: String {
            switch self {
            case .create: "New Folder"
            case .rename: "Rename Folder"
            }
        }
        var confirmLabel: String {
            switch self {
            case .create: "Create"
            case .rename: "Save"
            }
        }
    }

    let mode: Mode
    let onCommit: (String, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var iconData: Data?
    @State private var selectedPhoto: PhotosPickerItem?

    init(mode: Mode, onCommit: @escaping (String, Data?) -> Void) {
        self.mode = mode
        self.onCommit = onCommit
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _iconData = State(initialValue: nil)
        case .rename(let folder):
            _name = State(initialValue: folder.name)
            _iconData = State(initialValue: folder.iconData)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        iconPreview
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .frostedRow()

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    .frostedRow()

                    if iconData != nil {
                        Button("Remove Icon", role: .destructive) {
                            iconData = nil
                            selectedPhoto = nil
                        }
                        .frostedRow()
                    }
                } header: {
                    Text("Icon")
                }

                Section {
                    TextField("Folder Name", text: $name)
                        .frostedRow()
                } header: {
                    Text("Name")
                }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            .presentationBackground {
                ZStack {
                    Image("LaunchBackground")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                }
            }
            #endif
            .navigationTitle(mode.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.confirmLabel) {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onCommit(trimmed, iconData)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .principal) {
                    Text(mode.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.85, green: 0.20, blue: 0.0),
                                    Color(red: 1.0, green: 0.62, blue: 0.08)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let raw = try? await item?.loadTransferable(type: Data.self) {
                        iconData = makeThumbnail(from: raw)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var iconPreview: some View {
        if let data = iconData, let img = PlatformImage(data: data) {
            Image(platformImage: img)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Circle().fill(Color.secondary.opacity(0.18))
                Image(systemName: "folder")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Thumbnail

/// Resizes raw image data to a square thumbnail using ImageIO (cross-platform).
private func makeThumbnail(from data: Data, maxDimension: Int = 256) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}
