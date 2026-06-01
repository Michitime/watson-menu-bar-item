import Foundation
import ServiceManagement

enum AppStorageKeys {
    static let showTrackingInMenuBar = "showTrackingInMenuBar"
    static let showProjectInMenuBar = "showProjectInMenuBar"
    static let autoStopEnabled = "autoStopEnabled"
    static let autoStopSecondsSinceMidnight = "autoStopSecondsSinceMidnight"
    static let autoStopTargetTimestamp = "autoStopTargetTimestamp"
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published private(set) var status: WatsonStatus = .loading
    @Published private(set) var isWorking = false
    @Published private(set) var inlineMessage: String?
    @Published private(set) var launchAtLoginIsOn = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var launchAtLoginStatusText: String?
    @Published private(set) var autoStopIsOn = false
    @Published private(set) var autoStopTime = Date()
    @Published private(set) var autoStopStatusText: String?
    @Published private(set) var autoStopStatusIsError = false
    @Published private var currentDate = Date()

    private let service: WatsonService
    private let defaults: UserDefaults
    private var launchRefreshTask: Task<Void, Never>?
    private var counterTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private var elapsedBaselineSeconds: TimeInterval?
    private var elapsedBaselineDate: Date?
    private var activeSessionDailyBaseline: ActiveSessionDailyBaseline?
    private static let counterIntervalNanoseconds: UInt64 = 1_000_000_000
    private static let defaultAutoStopSecondsSinceMidnight = 17 * 3_600

    init(service: WatsonService = WatsonService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        refreshAutoStopState()
        refreshLaunchAtLoginStatus()
        refreshOnLaunch()
        startCounter()
    }

    deinit {
        launchRefreshTask?.cancel()
        counterTask?.cancel()
        autoStopTask?.cancel()
    }

    var menuBarSymbolName: String {
        switch status.state {
        case .running:
            return "square.and.pencil"
        case .idle:
            return "cup.and.saucer.fill"
        case .loading:
            return "hourglass.circle"
        case .unavailable, .error:
            return "exclamationmark.circle"
        }
    }

    var menuBarTitle: String {
        menuBarTitle(showProject: true, showTimer: true) ?? ""
    }

    var runningElapsedText: String? {
        runningElapsedSeconds.map(formattedCounter)
    }

    func menuBarTitle(showProject: Bool, showTimer: Bool) -> String? {
        switch status.state {
        case .running:
            let elapsedText = runningElapsedSeconds.map(formattedCounter) ?? "00:00"
            var components: [String] = []

            if showProject {
                components.append(compactProjectName(status.project ?? "Tracking"))
            }

            if showTimer {
                components.append(elapsedText)
            }

            return components.isEmpty ? nil : components.joined(separator: " ")
        case .idle:
            return showProject || showTimer ? "On break" : nil
        case .loading:
            return showProject || showTimer ? "..." : nil
        case .unavailable:
            return showProject || showTimer ? "Install" : nil
        case .error:
            return showProject || showTimer ? "Error" : nil
        }
    }

    private var runningElapsedSeconds: TimeInterval? {
        guard
            status.isRunning,
            let elapsedBaselineSeconds,
            let elapsedBaselineDate
        else {
            return nil
        }

        return max(0, elapsedBaselineSeconds + currentDate.timeIntervalSince(elapsedBaselineDate))
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

    var projectAutocompleteCandidates: [String] {
        let reportProjects = autocompleteReports.flatMap { report in
            report.summaries.map(\.projectName) + report.entries.map(\.projectName)
        }

        return uniqueAutocompleteCandidates([status.project].compactMap { $0 } + reportProjects)
    }

    var tagAutocompleteCandidates: [String] {
        let reportTags = autocompleteReports.flatMap { report in
            report.summaries.flatMap { tagCandidates(from: $0.tags) } +
                report.entries.flatMap { tagCandidates(from: $0.tags) }
        }

        return uniqueAutocompleteCandidates(status.tags + reportTags)
    }

    func refresh() async {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer {
            isWorking = false
        }

        let updatedStatus = await service.fetchStatus()
        apply(updatedStatus)

        if updatedStatus.state != .error && updatedStatus.state != .unavailable {
            inlineMessage = nil
        }
    }

    func start(project: String, tagsInput: String) async {
        guard !isWorking else {
            return
        }

        let trimmedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedProject.isEmpty else {
            inlineMessage = "Enter a project name before starting Watson."
            return
        }

        let normalizedTags = service.normalizedTags(from: tagsInput)
        let existingTotal = dailyTotalSeconds(
            project: trimmedProject,
            tags: normalizedTags,
            in: status.todayReport
        )

        activeSessionDailyBaseline = ActiveSessionDailyBaseline(
            project: trimmedProject,
            tags: normalizedTags,
            previousTotalInSeconds: existingTotal
        )

        isWorking = true
        inlineMessage = nil
        defer {
            isWorking = false
        }

        do {
            try await service.start(project: trimmedProject, tagsInput: tagsInput)
        } catch {
            activeSessionDailyBaseline = nil
            inlineMessage = error.localizedDescription
        }

        apply(await service.fetchStatus())
    }

    private struct ActiveSessionDailyBaseline {
        let project: String
        let tags: [String]
        let previousTotalInSeconds: Int
    }

    private func dailyTotalSeconds(project: String, tags: [String], in report: WatsonDailyReport) -> Int {
        report.summaries
            .filter { summary in
                summary.projectName == project && tagIdentity(summary.tags) == tagIdentity(tags)
            }
            .reduce(0) { $0 + $1.totalDurationInSeconds }
    }

    private func tagIdentity(_ tagsText: String?) -> [String] {
        guard var tagsText = tagsText?.trimmingCharacters(in: .whitespacesAndNewlines), !tagsText.isEmpty else {
            return []
        }

        if tagsText.hasPrefix("[") && tagsText.hasSuffix("]") {
            tagsText = String(tagsText.dropFirst().dropLast())
        }

        return tagIdentity(
            tagsText
                .split { $0 == "," || $0 == ";" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private func tagIdentity(_ tags: [String]) -> [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private func dailyCounterBaselineSeconds(for updatedStatus: WatsonStatus) -> TimeInterval? {
        guard updatedStatus.isRunning, let project = updatedStatus.project else {
            return elapsedSeconds(from: updatedStatus.elapsed)
        }

        let currentSessionSeconds = elapsedSeconds(from: updatedStatus.elapsed)
            .map { Int($0.rounded(.down)) }

        var candidates: [Int] = []
        let reportedDailyTotal = dailyTotalSeconds(
            project: project,
            tags: updatedStatus.tags,
            in: updatedStatus.todayReport
        )

        if reportedDailyTotal > 0 {
            candidates.append(reportedDailyTotal)
        }

        if
            let activeSessionDailyBaseline,
            activeSessionDailyBaseline.project == project,
            tagIdentity(activeSessionDailyBaseline.tags) == tagIdentity(updatedStatus.tags)
        {
            candidates.append(activeSessionDailyBaseline.previousTotalInSeconds + (currentSessionSeconds ?? 0))
        } else {
            activeSessionDailyBaseline = nil
        }

        if let bestCandidate = candidates.max() {
            return TimeInterval(bestCandidate)
        }

        return currentSessionSeconds.map(TimeInterval.init)
    }

    func stop() async {
        await perform {
            try await self.service.stop()
        }
    }

    func setAutoStop(_ isOn: Bool) {
        autoStopIsOn = isOn
        defaults.set(isOn, forKey: AppStorageKeys.autoStopEnabled)

        if isOn {
            updateAutoStopSchedule()
        } else {
            cancelAutoStopSchedule()
            defaults.removeObject(forKey: AppStorageKeys.autoStopTargetTimestamp)
            autoStopStatusText = nil
            autoStopStatusIsError = false
        }
    }

    func setAutoStopTime(_ date: Date) {
        autoStopTime = dateForToday(secondsSinceMidnight: secondsSinceMidnight(from: date))
        defaults.set(secondsSinceMidnight(from: autoStopTime), forKey: AppStorageKeys.autoStopSecondsSinceMidnight)

        if autoStopIsOn {
            updateAutoStopSchedule()
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

    private func refreshOnLaunch() {
        guard launchRefreshTask == nil else {
            return
        }

        launchRefreshTask = Task { [weak self] in
            await self?.refresh()
        }
    }

    private func startCounter() {
        guard counterTask == nil else {
            return
        }

        counterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.counterIntervalNanoseconds)
                self?.tickCounterIfRunning()
            }
        }
    }

    private func tickCounterIfRunning() {
        if status.isRunning {
            currentDate = Date()
        }
    }

    private var autocompleteReports: [WatsonDailyReport] {
        [status.todayReport] + status.workWeekReport.days.map(\.report)
    }

    private func tagCandidates(from tagsText: String?) -> [String] {
        guard var text = tagsText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return []
        }

        if text.hasPrefix("[") && text.hasSuffix("]") {
            text = String(text.dropFirst().dropLast())
        }

        return text
            .split { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func uniqueAutocompleteCandidates(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueValues: [String] = []

        for value in values {
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else {
                continue
            }

            let key = trimmedValue.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }

            uniqueValues.append(trimmedValue)
        }

        return uniqueValues
    }

    private func refreshAutoStopState() {
        autoStopIsOn = defaults.bool(forKey: AppStorageKeys.autoStopEnabled)
        autoStopTime = dateForToday(secondsSinceMidnight: storedAutoStopSecondsSinceMidnight())

        guard autoStopIsOn else {
            return
        }

        if let targetDate = storedAutoStopTargetDate() {
            scheduleAutoStop(for: targetDate)
            updateAutoStopStatus(for: targetDate)
        } else {
            let targetDate = targetDateForToday()

            if targetDate > Date() {
                saveAutoStopTarget(targetDate)
                scheduleAutoStop(for: targetDate)
                updateAutoStopStatus(for: targetDate)
            } else {
                autoStopStatusText = "Choose a future time for today."
                autoStopStatusIsError = true
            }
        }
    }

    private func updateAutoStopSchedule() {
        let targetDate = targetDateForToday()

        guard targetDate > Date() else {
            cancelAutoStopSchedule()
            defaults.removeObject(forKey: AppStorageKeys.autoStopTargetTimestamp)
            autoStopStatusText = "Choose a future time for today."
            autoStopStatusIsError = true
            return
        }

        saveAutoStopTarget(targetDate)
        scheduleAutoStop(for: targetDate)
        updateAutoStopStatus(for: targetDate)
    }

    private func scheduleAutoStop(for targetDate: Date) {
        cancelAutoStopSchedule()

        autoStopTask = Task { [weak self] in
            let delay = max(0, targetDate.timeIntervalSinceNow)
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard !Task.isCancelled else {
                return
            }

            await self?.runAutoStop(targetDate: targetDate)
        }
    }

    private func runAutoStop(targetDate: Date) async {
        guard autoStopIsOn else {
            return
        }

        isWorking = true
        inlineMessage = nil

        let currentStatus = await service.fetchStatus()
        guard currentStatus.isRunning else {
            clearAutoStop()
            apply(currentStatus)
            isWorking = false
            return
        }

        do {
            try await service.stop(at: targetDate)
            clearAutoStop()
        } catch {
            clearAutoStop()
            inlineMessage = error.localizedDescription
        }

        apply(await service.fetchStatus())
        isWorking = false
    }

    private func clearAutoStop() {
        cancelAutoStopSchedule()
        autoStopIsOn = false
        autoStopStatusText = nil
        autoStopStatusIsError = false
        defaults.set(false, forKey: AppStorageKeys.autoStopEnabled)
        defaults.removeObject(forKey: AppStorageKeys.autoStopTargetTimestamp)
    }

    private func cancelAutoStopSchedule() {
        autoStopTask?.cancel()
        autoStopTask = nil
    }

    private func saveAutoStopTarget(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: AppStorageKeys.autoStopTargetTimestamp)
    }

    private func storedAutoStopTargetDate() -> Date? {
        guard defaults.object(forKey: AppStorageKeys.autoStopTargetTimestamp) != nil else {
            return nil
        }

        return Date(timeIntervalSince1970: defaults.double(forKey: AppStorageKeys.autoStopTargetTimestamp))
    }

    private func storedAutoStopSecondsSinceMidnight() -> Int {
        guard defaults.object(forKey: AppStorageKeys.autoStopSecondsSinceMidnight) != nil else {
            return Self.defaultAutoStopSecondsSinceMidnight
        }

        return defaults.integer(forKey: AppStorageKeys.autoStopSecondsSinceMidnight)
    }

    private func secondsSinceMidnight(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        return (hour * 3_600) + (minute * 60)
    }

    private func dateForToday(secondsSinceMidnight: Int, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .second, value: secondsSinceMidnight, to: startOfDay) ?? startOfDay
    }

    private func targetDateForToday() -> Date {
        dateForToday(secondsSinceMidnight: secondsSinceMidnight(from: autoStopTime))
    }

    private func updateAutoStopStatus(for targetDate: Date) {
        autoStopStatusText = "Stops today at \(formattedAutoStopTime(targetDate))."
        autoStopStatusIsError = false
    }

    private func formattedAutoStopTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func perform(_ operation: @escaping () async throws -> Void) async {
        isWorking = true
        inlineMessage = nil

        do {
            try await operation()
        } catch {
            inlineMessage = error.localizedDescription
        }

        apply(await service.fetchStatus())
        isWorking = false
    }

    private func apply(_ updatedStatus: WatsonStatus) {
        let updatedDate = Date()
        status = updatedStatus
        currentDate = updatedDate

        if updatedStatus.isRunning {
            elapsedBaselineSeconds = dailyCounterBaselineSeconds(for: updatedStatus) ?? 0
            elapsedBaselineDate = updatedDate
        } else {
            activeSessionDailyBaseline = nil
            elapsedBaselineSeconds = nil
            elapsedBaselineDate = nil
        }
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

    private func elapsedSeconds(from text: String?) -> TimeInterval? {
        guard let text else {
            return nil
        }

        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !lowercased.isEmpty else {
            return nil
        }

        if let clockSeconds = clockDurationSeconds(from: lowercased) {
            return TimeInterval(clockSeconds)
        }

        let pattern = #"(?:(\d+)|an?|one)\s*([a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(lowercased.startIndex..<lowercased.endIndex, in: lowercased)
        let matches = regex.matches(in: lowercased, range: range)
        var totalSeconds = 0
        var matchedDurationUnit = false

        for match in matches {
            guard
                let unitRange = Range(match.range(at: 2), in: lowercased),
                let multiplier = secondsMultiplier(for: String(lowercased[unitRange]))
            else {
                continue
            }

            let value: Int
            if
                let valueRange = Range(match.range(at: 1), in: lowercased),
                let parsedValue = Int(lowercased[valueRange])
            {
                value = parsedValue
            } else {
                value = 1
            }

            totalSeconds += value * multiplier
            matchedDurationUnit = true
        }

        return matchedDurationUnit ? TimeInterval(totalSeconds) : nil
    }

    private func clockDurationSeconds(from text: String) -> Int? {
        let parts = text.split(separator: ":")

        guard
            (2...3).contains(parts.count),
            parts.allSatisfy({ part in part.allSatisfy(\.isNumber) }),
            let first = Int(parts[0]),
            let second = Int(parts[1])
        else {
            return nil
        }

        if parts.count == 2 {
            return first * 60 + second
        }

        guard let third = Int(parts[2]) else {
            return nil
        }

        return first * 3_600 + second * 60 + third
    }

    private func secondsMultiplier(for unit: String) -> Int? {
        switch unit {
        case "s", "sec", "secs", "second", "seconds":
            return 1
        case "m", "min", "mins", "minute", "minutes":
            return 60
        case "h", "hr", "hrs", "hour", "hours":
            return 3_600
        case "d", "day", "days":
            return 86_400
        case "w", "week", "weeks":
            return 604_800
        default:
            return nil
        }
    }

    private func formattedCounter(from seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func compactProjectName(_ project: String) -> String {
        let maxLength = 18

        guard project.count > maxLength else {
            return project
        }

        return "\(project.prefix(maxLength))..."
    }

}
