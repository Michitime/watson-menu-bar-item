import Foundation

struct WatsonStatus: Equatable {
    enum State: Equatable {
        case loading
        case running
        case idle
        case unavailable
        case error
    }

    let state: State
    let project: String?
    let tags: [String]
    let elapsed: String?
    let todayReport: WatsonDailyReport
    let message: String?
    let executablePath: String?

    static let loading = WatsonStatus(
        state: .loading,
        project: nil,
        tags: [],
        elapsed: nil,
        todayReport: WatsonDailyReport(entries: []),
        message: "Checking Watson...",
        executablePath: nil
    )

    static func running(
        project: String,
        tags: [String],
        elapsed: String?,
        todayReport: WatsonDailyReport,
        executablePath: String
    ) -> WatsonStatus {
        WatsonStatus(
            state: .running,
            project: project,
            tags: tags,
            elapsed: elapsed,
            todayReport: todayReport,
            message: nil,
            executablePath: executablePath
        )
    }

    static func idle(executablePath: String) -> WatsonStatus {
        WatsonStatus(
            state: .idle,
            project: nil,
            tags: [],
            elapsed: nil,
            todayReport: WatsonDailyReport(entries: []),
            message: nil,
            executablePath: executablePath
        )
    }

    static func unavailable() -> WatsonStatus {
        WatsonStatus(
            state: .unavailable,
            project: nil,
            tags: [],
            elapsed: nil,
            todayReport: WatsonDailyReport(entries: []),
            message: "Install Watson CLI and make sure `watson` is available in PATH, /opt/homebrew/bin, or /usr/local/bin.",
            executablePath: nil
        )
    }

    static func error(_ message: String, executablePath: String?) -> WatsonStatus {
        WatsonStatus(
            state: .error,
            project: nil,
            tags: [],
            elapsed: nil,
            todayReport: WatsonDailyReport(entries: []),
            message: message,
            executablePath: executablePath
        )
    }

    var isRunning: Bool {
        state == .running
    }

    var isUnavailable: Bool {
        state == .unavailable
    }

    var displayTitle: String {
        switch state {
        case .loading:
            return "Checking Watson"
        case .running:
            return "Tracking now"
        case .idle:
            return "Idle"
        case .unavailable:
            return "Watson not found"
        case .error:
            return "Unable to refresh"
        }
    }

    var primaryLine: String? {
        switch state {
        case .loading:
            return "Looking for the Watson CLI."
        case .running:
            return project
        case .idle:
            return "No active frame."
        case .unavailable, .error:
            return message
        }
    }

    var tagsLine: String? {
        guard isRunning, !tags.isEmpty else {
            return nil
        }

        return tags.map { "#\($0)" }.joined(separator: " ")
    }
}
