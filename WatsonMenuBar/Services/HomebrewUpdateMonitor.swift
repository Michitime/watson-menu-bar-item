import AppKit
import Foundation

@MainActor
final class HomebrewUpdateMonitor: ObservableObject {
    @Published private(set) var state: HomebrewUpdateState = .current

    private let launchedVersion: AppBundleVersion?
    private let bundleURL: URL
    private let infoDictionaryLoader: (URL) -> [String: Any]?
    private let relauncher: (URL) throws -> Void
    private let terminator: () -> Void
    private var timer: Timer?

    init(
        bundle: Bundle = .main,
        checkInterval: TimeInterval = 300,
        infoDictionaryLoader: @escaping (URL) -> [String: Any]? = HomebrewUpdateMonitor.loadInfoDictionary(from:),
        relauncher: @escaping (URL) throws -> Void = HomebrewUpdateMonitor.openNewAppInstance(at:),
        terminator: (() -> Void)? = nil
    ) {
        self.launchedVersion = bundle.infoDictionary.flatMap(AppBundleVersion.init(infoDictionary:))
        self.bundleURL = bundle.bundleURL
        self.infoDictionaryLoader = infoDictionaryLoader
        self.relauncher = relauncher
        self.terminator = terminator ?? { NSApp.terminate(nil) }

        refresh()
        startTimer(interval: checkInterval)
    }

    deinit {
        timer?.invalidate()
    }

    var menuBarHelpText: String? {
        switch state {
        case .updatedOnDisk:
            return "WatsonMenuBar was updated on disk and needs restart."
        case .restartFailed(let message, _):
            return "WatsonMenuBar restart failed: \(message)"
        case .current:
            return nil
        }
    }

    var canRestartToUpdate: Bool {
        switch state {
        case .updatedOnDisk, .restartFailed:
            return true
        case .current:
            return false
        }
    }

    func refresh() {
        guard
            let launchedVersion,
            let installedVersion = installedVersion()
        else {
            state = .current
            return
        }

        guard Self.isOnDiskVersionNewer(launched: launchedVersion, onDisk: installedVersion) else {
            state = .current
            return
        }

        if case .restartFailed(_, let failedInstalled) = state, failedInstalled == installedVersion {
            return
        }

        state = .updatedOnDisk(installed: installedVersion)
    }

    func restartToUpdate() {
        guard canRestartToUpdate else {
            return
        }

        let installedVersion = installedVersion()

        do {
            try relauncher(bundleURL)
            terminator()
        } catch {
            state = .restartFailed(message: error.localizedDescription, installed: installedVersion)
        }
    }

    static func isOnDiskVersionNewer(launched: AppBundleVersion, onDisk: AppBundleVersion) -> Bool {
        switch compareVersionStrings(onDisk.version, launched.version) {
        case .orderedDescending:
            return true
        case .orderedAscending:
            return false
        case .orderedSame:
            return compareVersionStrings(onDisk.build, launched.build) == .orderedDescending
        }
    }

    private func startTimer(interval: TimeInterval) {
        guard interval > 0 else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func installedVersion() -> AppBundleVersion? {
        let infoPlistURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)

        return infoDictionaryLoader(infoPlistURL).flatMap(AppBundleVersion.init(infoDictionary:))
    }

    private nonisolated static func loadInfoDictionary(from url: URL) -> [String: Any]? {
        NSDictionary(contentsOf: url) as? [String: Any]
    }

    private nonisolated static func openNewAppInstance(at bundleURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]
        try process.run()
    }

    private static func compareVersionStrings(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = versionComponents(from: lhs)
        let rhsComponents = versionComponents(from: rhs)
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let lhsComponent = index < lhsComponents.count ? lhsComponents[index] : .number(0)
            let rhsComponent = index < rhsComponents.count ? rhsComponents[index] : .number(0)
            let result = lhsComponent.compare(rhsComponent)

            if result != .orderedSame {
                return result
            }
        }

        return .orderedSame
    }

    private static func versionComponents(from version: String) -> [VersionComponent] {
        version
            .split { !$0.isLetter && !$0.isNumber }
            .map { part in
                if let number = Int(part) {
                    return .number(number)
                }

                return .text(String(part).lowercased())
            }
    }
}

private enum VersionComponent {
    case number(Int)
    case text(String)

    func compare(_ other: VersionComponent) -> ComparisonResult {
        switch (self, other) {
        case (.number(let lhs), .number(let rhs)):
            if lhs == rhs {
                return .orderedSame
            }

            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (.text(let lhs), .text(let rhs)):
            return lhs.compare(rhs, options: .numeric)
        case (.number, .text):
            return .orderedDescending
        case (.text, .number):
            return .orderedAscending
        }
    }
}
