import Foundation

enum AppUpdateState: Equatable {
    case notConfigured
    case idle
    case checking
    case available(version: String)
    case downloading(version: String)
    case downloaded(version: String)
    case readyToRestart(version: String)
    case installing(version: String?)
    case error(String)

    var showsMenuBarBadge: Bool {
        switch self {
        case .available, .downloading, .downloaded, .readyToRestart:
            return true
        case .notConfigured, .idle, .checking, .installing, .error:
            return false
        }
    }

    var noticeTitle: String? {
        switch self {
        case .available(let version):
            return "Update \(version) available"
        case .downloading(let version):
            return "Downloading update \(version)"
        case .downloaded(let version):
            return "Update \(version) downloaded"
        case .readyToRestart(let version):
            return "Update \(version) ready"
        case .installing:
            return "Installing update"
        case .error:
            return "Update check failed"
        case .notConfigured, .idle, .checking:
            return nil
        }
    }

    var noticeDetail: String? {
        switch self {
        case .available:
            return "Open the updater to review and install it."
        case .downloading:
            return "The update will be ready to restart shortly."
        case .downloaded:
            return "Restart to finish installing the update."
        case .readyToRestart:
            return "Restart now to finish installing the update."
        case .installing:
            return "WatsonMenuBar will relaunch when installation finishes."
        case .error(let message):
            return message
        case .notConfigured, .idle, .checking:
            return nil
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .available:
            return "View Update"
        case .downloaded, .readyToRestart:
            return "Update and Restart"
        case .error:
            return "Check Again"
        case .notConfigured, .idle, .checking, .downloading, .installing:
            return nil
        }
    }

    var replacesQuitAction: Bool {
        switch self {
        case .downloaded, .readyToRestart:
            return true
        case .notConfigured, .idle, .checking, .available, .downloading, .installing, .error:
            return false
        }
    }

    var primaryActionSymbolName: String {
        switch self {
        case .downloaded, .readyToRestart:
            return "arrow.clockwise.circle.fill"
        case .error:
            return "arrow.triangle.2.circlepath"
        case .available, .notConfigured, .idle, .checking, .downloading, .installing:
            return "arrow.down.circle.fill"
        }
    }
}
