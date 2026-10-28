import AppKit

enum NavigationFailure: LocalizedError {
    case invalidThread, missingApplication
    var errorDescription: String? {
        switch self {
        case .invalidThread: return "会话标识无效，此条目会继续保留。"
        case .missingApplication: return "没有找到正在运行或已安装的 ChatGPT / Codex 桌面应用。"
        }
    }
}

final class ThreadNavigator {
    typealias Completion = (Result<Void, Error>) -> Void
    typealias Opener = (URL, URL, @escaping Completion) -> Void
    private let resolveApplication: () -> URL?
    private let openURL: Opener

    init(resolveApplication: @escaping () -> URL? = ThreadNavigator.currentApplication,
         openURL: @escaping Opener = ThreadNavigator.openInApplication) {
        self.resolveApplication = resolveApplication
        self.openURL = openURL
    }

    static func threadURL(id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw NavigationFailure.invalidThread }
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(id)"
        // This adapter reads local sessions. Do not let the currently selected
        // remote connection or a catalog hint choose a different host.
        components.queryItems = [URLQueryItem(name: "hostId", value: "local")]
        guard let url = components.url else { throw NavigationFailure.invalidThread }
        return url
    }

    func open(threadID: String, completion: @escaping Completion) {
        do {
            let url = try Self.threadURL(id: threadID)
            guard let application = resolveApplication() else { throw NavigationFailure.missingApplication }
            openURL(url, application, completion)
        } catch { completion(.failure(error)) }
    }

    private static func currentApplication() -> URL? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        return running.first(where: { !$0.isTerminated && $0.isActive })?.bundleURL
            ?? running.first(where: { !$0.isTerminated })?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
    }

    private static func openInApplication(_ url: URL, _ application: URL, completion: @escaping Completion) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
        }
    }
}
