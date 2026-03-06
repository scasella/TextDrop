import AppKit
import SwiftUI

enum AllowedRoot: String, CaseIterable, Identifiable {
    case desktop
    case downloads
    case documents

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .downloads: return "Downloads"
        case .documents: return "Documents"
        }
    }

    var systemImage: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .downloads: return "arrow.down.circle"
        case .documents: return "doc.text"
        }
    }

    var searchPathDirectory: FileManager.SearchPathDirectory {
        switch self {
        case .desktop: return .desktopDirectory
        case .downloads: return .downloadsDirectory
        case .documents: return .documentDirectory
        }
    }

    func directoryURL(fileManager: FileManager = .default) -> URL {
        guard let url = fileManager.urls(for: searchPathDirectory, in: .userDomainMask).first else {
            preconditionFailure("Missing user directory for \(title)")
        }
        return SavePathRules.canonicalize(url)
    }

    static func resolvedURLs(fileManager: FileManager = .default) -> [URL] {
        allCases.map { $0.directoryURL(fileManager: fileManager) }
    }
}

enum SaveValidationError: LocalizedError, Equatable {
    case missingExtension
    case outsideAllowedRoots

    var errorDescription: String? {
        switch self {
        case .missingExtension:
            return "File names must include an extension."
        case .outsideAllowedRoots:
            return "Choose a location inside Desktop, Downloads, or Documents."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingExtension:
            return "Enter a file name like notes.txt, draft.md, or snippet.swift."
        case .outsideAllowedRoots:
            return "Pick a folder inside your Desktop, Downloads, or Documents directory."
        }
    }

    var code: Int {
        switch self {
        case .missingExtension: return 1
        case .outsideAllowedRoots: return 2
        }
    }

    func asNSError() -> NSError {
        NSError(
            domain: "TextDrop.SaveValidation",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: errorDescription ?? "Save validation failed.",
                NSLocalizedRecoverySuggestionErrorKey: recoverySuggestion ?? ""
            ]
        )
    }
}

enum SavePathRules {
    static func validate(destinationURL: URL, allowedRoots: [URL]) -> SaveValidationError? {
        let fileName = destinationURL.lastPathComponent
        let hasExtension = !destinationURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard !fileName.isEmpty, hasExtension else {
            return .missingExtension
        }

        let directory = canonicalize(destinationURL.deletingLastPathComponent())
        let canonicalRoots = allowedRoots.map(canonicalize)

        if canonicalRoots.contains(where: { isWithin(directory, root: $0) }) {
            return nil
        }

        return .outsideAllowedRoots
    }

    static func canonicalize(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func isWithin(_ directory: URL, root: URL) -> Bool {
        let directoryPath = canonicalize(directory).path
        let rootPath = canonicalize(root).path
        return directoryPath == rootPath || directoryPath.hasPrefix(rootPath + "/")
    }
}

final class SavePanelValidator: NSObject, NSOpenSavePanelDelegate {
    private let allowedRoots: [URL]

    init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots.map(SavePathRules.canonicalize)
        super.init()
    }

    @MainActor
    func panel(_ sender: Any, validate url: URL) throws {
        if let error = SavePathRules.validate(destinationURL: url, allowedRoots: allowedRoots) {
            throw error.asNSError()
        }
    }
}

enum StatusKind: Equatable {
    case success
    case error

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        }
    }
}

struct StatusMessage: Equatable {
    let kind: StatusKind
    let text: String
}

@MainActor
@Observable
final class TextDropStore {
    var text = ""
    var status: StatusMessage?
    var lastSaveDirectory: URL?

    var allowedRoots: [AllowedRoot] {
        AllowedRoot.allCases
    }

    var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusGeneration = 0

    func clearText() {
        text = ""
        showStatus("Editor cleared.", kind: .success)
    }

    func saveToFile() {
        let panel = NSSavePanel()
        let validator = SavePanelValidator(allowedRoots: AllowedRoot.resolvedURLs())

        panel.title = "Create File"
        panel.message = "Choose a name, extension, and folder inside Desktop, Downloads, or Documents."
        panel.prompt = "Create File"
        panel.nameFieldStringValue = "untitled.txt"
        panel.canCreateDirectories = true
        panel.canSelectHiddenExtension = true
        panel.isExtensionHidden = false
        panel.directoryURL = lastSaveDirectory ?? AllowedRoot.desktop.directoryURL()
        panel.delegate = validator

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastSaveDirectory = SavePathRules.canonicalize(url.deletingLastPathComponent())
            let location = relativeLocationDescription(for: url)
            showStatus("Created \(url.lastPathComponent) in \(location).", kind: .success)
        } catch {
            showStatus("Save failed: \(error.localizedDescription)", kind: .error)
        }
    }

    private func relativeLocationDescription(for url: URL) -> String {
        let path = url.deletingLastPathComponent().path
        let homePath = NSHomeDirectory()

        if path.hasPrefix(homePath + "/") {
            return "~" + String(path.dropFirst(homePath.count))
        }

        if path == homePath {
            return "~"
        }

        return path
    }

    private func showStatus(_ message: String, kind: StatusKind) {
        statusGeneration += 1
        let generation = statusGeneration
        status = StatusMessage(kind: kind, text: message)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.statusGeneration == generation else { return }
            self.status = nil
        }
    }
}

struct TextDropContentView: View {
    @State private var store = TextDropStore()
    @FocusState private var editorFocused: Bool

    var body: some View {
        AdaptiveGlassContainer(spacing: 14) {
            VStack(spacing: 10) {
                AdaptiveCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("TextDrop")
                                        .font(.headline.weight(.semibold))
                                    Text("Paste text, then use Save...")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.tint)
                            }

                            Spacer()
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                ForEach(store.allowedRoots) { root in
                                    AllowedRootBadge(root: root)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(store.allowedRoots) { root in
                                    AllowedRootBadge(root: root)
                                }
                            }
                        }
                    }
                }

                editorSection

                AdaptiveCard {
                    HStack(alignment: .center, spacing: 10) {
                        footerInfo

                        Spacer()

                        Button("Clear") {
                            store.clearText()
                            editorFocused = true
                        }
                        .buttonStyle(.bordered)

                        saveButton

                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .frame(width: 368)
            .padding(12)
            .background(backgroundFill)
            .animation(.easeInOut(duration: 0.18), value: store.status)
        }
        .onAppear {
            DispatchQueue.main.async {
                editorFocused = true
            }
        }
    }

    private var editorSection: some View {
        AdaptiveCard {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )

                if store.text.isEmpty {
                    Text("Paste text here. Save lets you choose the file name, extension, and folder.")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                }

                TextEditor(text: $store.text)
                    .font(.system(.body, design: .monospaced))
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.clear)
            }
            .frame(minHeight: 230)
        }
    }

    @ViewBuilder
    private var footerInfo: some View {
        if let status = store.status {
            HStack(spacing: 6) {
                Image(systemName: status.kind.icon)
                    .foregroundStyle(status.kind.tint)
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .transition(.opacity)
        } else {
            Text("\(store.text.count) characters")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if #available(macOS 26, *) {
            Button("Save...") {
                store.saveToFile()
                editorFocused = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .disabled(!store.canSave)
        } else {
            Button("Save...") {
                store.saveToFile()
                editorFocused = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!store.canSave)
        }
    }

    @ViewBuilder
    private var backgroundFill: some View {
        if #available(macOS 26, *) {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.12),
                    Color(nsColor: .windowBackgroundColor).opacity(0.90),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}

struct AllowedRootBadge: View {
    let root: AllowedRoot

    var body: some View {
        if #available(macOS 26, *) {
            Label(root.title, systemImage: root.systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(.accentColor.opacity(0.06)), in: .capsule)
        } else {
            Label(root.title, systemImage: root.systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct AdaptiveCard<Content: View>: View {
    private let tint: Color
    private let content: Content

    init(tint: Color = .accentColor.opacity(0.04), @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 20))
        } else {
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
        }
    }
}

#if !TESTING
@main
struct TextDropApp: App {
    var body: some Scene {
        MenuBarExtra("TextDrop", systemImage: "doc.badge.plus") {
            TextDropContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
#endif
