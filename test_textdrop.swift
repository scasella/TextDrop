import Foundation

var passed = 0
var failed = 0

func assert(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if condition() {
        passed += 1
        print("  [PASS] \(message)")
    } else {
        failed += 1
        print("  [FAIL] \(message) (\(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #fileID, line: Int = #line) {
    if actual == expected {
        passed += 1
        print("  [PASS] \(message)")
    } else {
        failed += 1
        print("  [FAIL] \(message) -> got \(actual), expected \(expected) (\(file):\(line))")
    }
}

func makeDirectory(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

func runTests() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent("textdrop-tests-\(UUID().uuidString)", isDirectory: true)
    let desktop = tempRoot.appendingPathComponent("Desktop", isDirectory: true)
    let downloads = tempRoot.appendingPathComponent("Downloads", isDirectory: true)
    let documents = tempRoot.appendingPathComponent("Documents", isDirectory: true)
    let outside = tempRoot.appendingPathComponent("Outside", isDirectory: true)

    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    try makeDirectory(desktop)
    try makeDirectory(downloads)
    try makeDirectory(documents)
    try makeDirectory(outside)
    try makeDirectory(desktop.appendingPathComponent("nested/folder", isDirectory: true))

    let allowedRoots = [desktop, downloads, documents]

    print("validate(destinationURL:allowedRoots:)")
    assertEqual(
        SavePathRules.validate(
            destinationURL: desktop.appendingPathComponent("note.txt"),
            allowedRoots: allowedRoots
        ),
        nil,
        "accepts file directly inside Desktop"
    )

    assertEqual(
        SavePathRules.validate(
            destinationURL: desktop.appendingPathComponent("nested/folder/draft.md"),
            allowedRoots: allowedRoots
        ),
        nil,
        "accepts nested subdirectories inside Desktop"
    )

    assertEqual(
        SavePathRules.validate(
            destinationURL: downloads.appendingPathComponent("snippet.swift"),
            allowedRoots: allowedRoots
        ),
        nil,
        "accepts Downloads destinations"
    )

    assertEqual(
        SavePathRules.validate(
            destinationURL: documents.appendingPathComponent("meeting.json"),
            allowedRoots: allowedRoots
        ),
        nil,
        "accepts Documents destinations"
    )

    assertEqual(
        SavePathRules.validate(
            destinationURL: outside.appendingPathComponent("bad.txt"),
            allowedRoots: allowedRoots
        ),
        .outsideAllowedRoots,
        "rejects destinations outside allowed roots"
    )

    assertEqual(
        SavePathRules.validate(
            destinationURL: desktop.appendingPathComponent("extensionless"),
            allowedRoots: allowedRoots
        ),
        .missingExtension,
        "rejects file names without an extension"
    )

    print("\nisWithin(_:root:)")
    assert(
        SavePathRules.isWithin(desktop.appendingPathComponent("nested/folder", isDirectory: true), root: desktop),
        "nested directories are recognized as descendants"
    )
    assert(
        !SavePathRules.isWithin(outside, root: desktop),
        "outside directory is not considered a descendant"
    )

    print("\nsymlink escape handling")
    let symlink = desktop.appendingPathComponent("shortcut", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
    assertEqual(
        SavePathRules.validate(
            destinationURL: symlink.appendingPathComponent("escape.txt"),
            allowedRoots: allowedRoots
        ),
        .outsideAllowedRoots,
        "rejects symlinked directories that escape allowed roots"
    )
}

@main
enum TextDropTests {
    static func main() {
        print("=== TextDrop Tests ===")

        do {
            try runTests()
        } catch {
            failed += 1
            print("[FAIL] Unexpected test harness error: \(error)")
        }

        print("\n=== Results: \(passed) passed, \(failed) failed ===")
        if failed > 0 {
            exit(1)
        }
    }
}
