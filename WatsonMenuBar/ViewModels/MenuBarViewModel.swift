import Foundation
import ServiceManagement

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var status: WatsonStatus = .loading
    @Published private(set) var isWorking = false
    @Published private(set) var inlineMessage: String?
    @Published private(set) var launchAtLoginIsOn = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var launchAtLoginStatusText: String?

    private let service: WatsonService
    private var refreshTask: Task<Void, Never>?
    private let refreshIntervalNanoseconds: UInt64 = 60_000_000_000

    init(service: WatsonService = WatsonService()) {
        self.service = service
        refreshLaunchAtLoginStatus()
        startRefreshing()
    }

    deinit {
        refreshTask?.cancel()
    }

    var menuBarSymbolName: String {
        switch status.state {
        case .running:
            return "record.circle"
        case .idle:
            return "pause.circle"
        case .loading:
            return "hourglass.circle"
        case .unavailable, .error:
            return "exclamationmark.circle"
        }
    }

    var menuBarTitle: String {
        switch status.state {
        case .running:
            return shortElapsed(from: status.elapsed) ?? "On"
        case .idle:
            return "Idle"
        case .loading:
            return "..."
        case .unavailable:
            return "Install"
        case .error:
            return "Error"
        }
    }

    var menuBarHelpText: String {
        switch status.state {
        case .running:
            return status.project.map { "Watson is tracking \($0)." } ?? "Watson is running."
        case .idle:
            return "Watson is idle."
        case .loading:
            return "Refreshing Watson status."
        case .unavailable:
            return "Watson CLI not found."
        case .error:
            return status.message ?? "Watson returned an error."
        }
    }

    var footerText: String? {
        if let inlineMessage {
            return inlineMessage
        }

        switch status.state {
        case .unavailable, .error:
            return status.message
        case .running, .idle:
            return status.executablePath.map { "Using \($0)" }
        case .loading:
            return nil
        }
    }

    var footerIsError: Bool {
        inlineMessage != nil || status.state == .unavailable || status.state == .error
    }

    var canEditInputs: Bool {
        !status.isUnavailable && !isWorking
    }

    var canStart: Bool {
        !status.isUnavailable && !isWorking
    }

    var canStop: Bool {
        status.isRunning && !status.isUnavailable && !isWorking
    }

    var canRefresh: Bool {
        !isWorking
    }

    func refresh() async {
        await refresh(silent: false)
    }

    func start(project: String, tagsInput: String) async {
        let trimmedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedProject.isEmpty else {
            inlineMessage = "Enter a project name before starting Watson."
            return
        }

        await perform {
            try await self.service.start(project: trimmedProject, tagsInput: tagsInput)
        }
    }

    func stop() async {
        await perform {
            try await self.service.stop()
        }
    }

    func setLaunchAtLogin(_ isOn: Bool) {
        launchAtLoginStatusText = nil
        var operationError: String?

        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            operationError = error.localizedDescription
        }

        refreshLaunchAtLoginStatus()

        if let operationError {
            launchAtLoginStatusText = operationError
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func startRefreshing() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            await self.refresh(silent: false)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.refreshIntervalNanoseconds)
                await self.refresh(silent: true)
            }
        }
    }

    private func refresh(silent: Bool) async {
        if silent && isWorking {
            return
        }

        if !silent {
            isWorking = true
        }

        let updatedStatus = await service.fetchStatus()
        status = updatedStatus

        if updatedStatus.state != .error && updatedStatus.state != .unavailable {
            inlineMessage = nil
        }

        if !silent {
            isWorking = false
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        inlineMessage = nil

        do {
            try await operation()
        } catch {
            inlineMessage = error.localizedDescription
        }

        status = await service.fetchStatus()
        isWorking = false
    }

    private func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginIsOn = true
            launchAtLoginNeedsApproval = false
            launchAtLoginStatusText = nil
        case .requiresApproval:
            launchAtLoginIsOn = true
            launchAtLoginNeedsApproval = true
            launchAtLoginStatusText = "Approve launch at login in System Settings."
        case .notRegistered:
            launchAtLoginIsOn = false
            launchAtLoginNeedsApproval = false
            launchAtLoginStatusText = nil
        case .notFound:
            launchAtLoginIsOn = false
            launchAtLoginNeedsApproval = false
            launchAtLoginStatusText = "Launch at login is unavailable for this build."
        @unknown default:
            launchAtLoginIsOn = false
            launchAtLoginNeedsApproval = false
            launchAtLoginStatusText = "Unable to read launch at login status."
        }
    }

    private func shortElapsed(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        let lowercased = text.lowercased()

        if lowercased.contains("second") {
            return "Now"
        }

        if lowercased.contains("an hour") || lowercased.contains("a hour") {
            return "1h"
        }

        if lowercased.contains("a minute") {
            return "1m"
        }

        let units: [(String, String)] = [
            ("minute", "m"),
            ("hour", "h"),
            ("day", "d"),
            ("week", "w"),
            ("month", "mo"),
            ("year", "y")
        ]

        for (unit, suffix) in units {
            if let value = leadingNumber(in: lowercased, before: unit) {
                return "\(value)\(suffix)"
            }
        }

        return nil
    }

    private func leadingNumber(in text: String, before unit: String) -> String? {
        let pattern = #"(\d+)\s+\#(unit)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[valueRange])
    }
}
