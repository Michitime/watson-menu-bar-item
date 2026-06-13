import Foundation

struct AppBundleVersion: Equatable {
    let version: String
    let build: String

    init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    init?(infoDictionary: [String: Any]) {
        guard
            let version = Self.trimmedInfoValue(infoDictionary["CFBundleShortVersionString"]),
            let build = Self.trimmedInfoValue(infoDictionary["CFBundleVersion"])
        else {
            return nil
        }

        self.version = version
        self.build = build
    }

    var displayText: String {
        "\(version) (\(build))"
    }

    private static func trimmedInfoValue(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}

enum HomebrewUpdateState: Equatable {
    case current
    case updatedOnDisk(installed: AppBundleVersion)
    case restartFailed(message: String, installed: AppBundleVersion?)

    var showsMenuBarBadge: Bool {
        switch self {
        case .updatedOnDisk, .restartFailed:
            return true
        case .current:
            return false
        }
    }

    var showsUpdateNotice: Bool {
        switch self {
        case .updatedOnDisk, .restartFailed:
            return true
        case .current:
            return false
        }
    }

    var noticeTitle: String {
        switch self {
        case .updatedOnDisk:
            return "Update installed"
        case .restartFailed:
            return "Restart failed"
        case .current:
            return ""
        }
    }

    var noticeDetail: String {
        switch self {
        case .updatedOnDisk(let installed):
            return "A newer Homebrew-installed copy is on disk. Restart to use \(installed.displayText)."
        case .restartFailed(let message, let installed):
            if let installed {
                return "Could not restart into \(installed.displayText): \(message)"
            }

            return "Could not restart WatsonMenuBar: \(message)"
        case .current:
            return ""
        }
    }

    var actionTitle: String? {
        switch self {
        case .updatedOnDisk, .restartFailed:
            return "Restart to Update"
        case .current:
            return nil
        }
    }

    var symbolName: String {
        switch self {
        case .updatedOnDisk:
            return "arrow.clockwise.circle.fill"
        case .restartFailed:
            return "exclamationmark.triangle.fill"
        case .current:
            return "checkmark.circle.fill"
        }
    }
}
