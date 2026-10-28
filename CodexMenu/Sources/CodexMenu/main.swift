import AppKit
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func argument(after name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let codexRoot = argument(after: "--codex-home").map { URL(fileURLWithPath: $0) }
let store = LocalSessionStore(root: codexRoot)
// Include turns missed by an older adapter during this repair, without changing
// the historical-conversation policy of normal launches.
let recoveryDate = argument(after: "--recover-since").flatMap(Double.init).flatMap {
    $0.isFinite ? Date(timeIntervalSince1970: $0) : nil
}

if arguments.contains("--snapshot") {
    do {
        let sessions = try store.scan(finishedSince: recoveryDate).filter {
            recoveryDate != nil || [.running, .waiting, .unknown].contains($0.status)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(sessions), as: UTF8.self))
    } catch {
        fputs("Codex Menu: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else if let path = argument(after: "--render-preview") {
    do { try renderMenuPreview(to: path, dark: arguments.contains("--dark"), largeFont: arguments.contains("--large-font")) }
    catch { fputs("Codex Menu: \(error.localizedDescription)\n", stderr); exit(1) }
} else if let path = argument(after: "--render-settings-preview") {
    do { try renderSettingsPreview(to: path, dark: arguments.contains("--dark"), largeFont: arguments.contains("--large-font")) }
    catch { fputs("Codex Menu: \(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    // A normal launch reuses the running menu app rather than creating duplicates.
    if let bundleID = Bundle.main.bundleIdentifier,
       NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
        exit(0)
    }
    let persistence = StatePersistence(url: argument(after: "--state-file").map { URL(fileURLWithPath: $0) })
    let delegate = MenuAppDelegate(reader: store, persistence: persistence, demo: arguments.contains("--demo"), monitoringSince: recoveryDate)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
