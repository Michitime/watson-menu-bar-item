import Foundation

struct WatsonService {
    enum ServiceError: LocalizedError {
        case executableNotFound
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .executableNotFound:
                return "Watson CLI is not installed. Install it and make sure `watson` is available in PATH, /opt/homebrew/bin, or /usr/local/bin."
            case .commandFailed(let message):
                return message
            }
        }
    }

    private let idleMessage = "No project started."
    private let fileManager = FileManager.default

    func fetchStatus() async -> WatsonStatus {
        guard let executable = resolveExecutablePath() else {
            return .unavailable()
        }

        do {
            let statusResult = try await run(executable: executable, arguments: ["status"])
            let statusText = cleaned(statusResult.combinedOutput)

            guard statusResult.exitCode == 0 else {
                return .error(
                    statusText.isEmpty ? "Watson returned an unexpected response." : statusText,
                    executablePath: executable
                )
            }

            let projectResult = try await run(executable: executable, arguments: ["status", "--project"])
            let tagsResult = try await run(executable: executable, arguments: ["status", "--tags"])
            let elapsedResult = try await run(executable: executable, arguments: ["status", "--elapsed"])

            if let failedResult = [projectResult, tagsResult, elapsedResult].first(where: { $0.exitCode != 0 }) {
                return .error(
                    commandFailureMessage(from: failedResult, fallback: "Unable to read Watson status."),
                    executablePath: executable
                )
            }

            let projectText = cleaned(projectResult.combinedOutput)
            let tagsText = cleaned(tagsResult.combinedOutput)
            let elapsedText = cleaned(elapsedResult.combinedOutput)
            let today = Date()
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
            let todayReport = try await fetchDailyReport(executable: executable, date: today)
            let yesterdayReport = try await fetchDailyReport(executable: executable, date: yesterday)
            let workWeekReport = try await fetchWorkWeekReport(executable: executable)

            if projectText == idleMessage || elapsedText == idleMessage {
                return WatsonStatus(
                    state: .idle,
                    project: nil,
                    tags: [],
                    elapsed: nil,
                    todayReport: todayReport,
                    yesterdayReport: yesterdayReport,
                    workWeekReport: workWeekReport,
                    message: nil,
                    executablePath: executable
                )
            }

            return .running(
                project: projectText.isEmpty ? "Unknown project" : projectText,
                tags: parseTags(from: tagsText),
                elapsed: elapsedText.isEmpty ? nil : elapsedText,
                todayReport: todayReport,
                yesterdayReport: yesterdayReport,
                workWeekReport: workWeekReport,
                executablePath: executable
            )
        } catch let error as ServiceError {
            switch error {
            case .executableNotFound:
                return .unavailable()
            case .commandFailed(let message):
                return .error(message, executablePath: executable)
            }
        } catch {
            return .error(error.localizedDescription, executablePath: executable)
        }
    }

    func start(project: String, tagsInput: String) async throws {
        let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProject.isEmpty else {
            throw ServiceError.commandFailed("Enter a project name before starting Watson.")
        }

        let executable = try executablePath()
        let tagArguments = normalizedTags(from: tagsInput).map { "+\($0)" }

        if try await isProjectStarted(executable: executable) {
            let stopResult = try await run(executable: executable, arguments: ["stop"])

            guard stopResult.exitCode == 0 else {
                throw ServiceError.commandFailed(
                    commandFailureMessage(from: stopResult, fallback: "Unable to stop the current Watson project.")
                )
            }
        }

        let result = try await run(executable: executable, arguments: ["start", normalizedProject] + tagArguments)

        guard result.exitCode == 0 else {
            throw ServiceError.commandFailed(
                commandFailureMessage(from: result, fallback: "Unable to start Watson.")
            )
        }
    }

    func stop() async throws {
        let executable = try executablePath()
        let result = try await run(executable: executable, arguments: ["stop"])

        guard result.exitCode == 0 else {
            throw ServiceError.commandFailed(
                commandFailureMessage(from: result, fallback: "Unable to stop Watson.")
            )
        }
    }

    func stop(at date: Date) async throws {
        let executable = try executablePath()
        let result = try await run(executable: executable, arguments: ["stop", "--at", watsonDateTimeString(from: date)])

        guard result.exitCode == 0 else {
            throw ServiceError.commandFailed(
                commandFailureMessage(from: result, fallback: "Unable to stop Watson.")
            )
        }
    }

    func normalizedTags(from text: String) -> [String] {
        var seen = Set<String>()

        return text
            .split { $0 == "," || $0 == ";" }
            .map(normalizedTag)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private func executablePath() throws -> String {
        guard let path = resolveExecutablePath() else {
            throw ServiceError.executableNotFound
        }

        return path
    }

    private func resolveExecutablePath() -> String? {
        if let pathExecutable = resolveFromPATH(named: "watson") {
            return pathExecutable
        }

        for candidate in ["/opt/homebrew/bin/watson", "/usr/local/bin/watson"] where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    private func resolveFromPATH(named executable: String) -> String? {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""

        for directory in pathValue.split(separator: ":") {
            let candidate = String(directory) + "/" + executable
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func normalizedTag(_ text: Substring) -> String {
        let plusCharacters = CharacterSet(charactersIn: "+")
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map { $0.trimmingCharacters(in: plusCharacters) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private func parseTags(from text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        guard text.hasPrefix("[") && text.hasSuffix("]") else {
            return [text]
        }

        let inner = text.dropFirst().dropLast()

        return inner
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func isProjectStarted(executable: String) async throws -> Bool {
        let result = try await run(executable: executable, arguments: ["status", "--project"])

        guard result.exitCode == 0 else {
            throw ServiceError.commandFailed(
                commandFailureMessage(from: result, fallback: "Unable to read Watson status.")
            )
        }

        let projectText = cleaned(result.combinedOutput)
        return !projectText.isEmpty && projectText != idleMessage
    }

    private func commandFailureMessage(from result: CommandResult, fallback: String) -> String {
        let message = cleaned(result.combinedOutput)
        return message.isEmpty ? fallback : message
    }

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        // Xcode injects preview/debug dyld variables that break Python-based CLIs like Watson.
        environment.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        environment.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
        environment.removeValue(forKey: "DYLD_LIBRARY_PATH")

        return environment
    }

    private func fetchWorkWeekReport(executable: String) async throws -> WatsonWorkWeekReport {
        let dates = currentWorkWeekDates()

        guard let firstDate = dates.first, let lastDate = dates.last else {
            return .empty
        }

        let reportsByStartDate = try await fetchReportsByStartDate(
            executable: executable,
            from: firstDate,
            to: lastDate,
            failureFallback: "Unable to read Watson work week."
        )

        let dayReports = dates.map { date in
            WatsonWorkWeekDayReport(
                date: date,
                report: reportsByStartDate[Calendar.current.startOfDay(for: date)] ?? WatsonDailyReport(entries: [])
            )
        }

        return WatsonWorkWeekReport(days: dayReports)
    }

    private func currentWorkWeekDates(referenceDate: Date = Date(), calendar baseCalendar: Calendar = .current) -> [Date] {
        var calendar = baseCalendar
        calendar.firstWeekday = 2

        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7

        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) else {
            return []
        }

        let dayOffsetLimit = min(daysSinceMonday, 4)
        return (0...dayOffsetLimit).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monday)
        }
    }

    private func watsonDateString(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return ""
        }

        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func watsonDateTimeString(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        guard
            let year = components.year,
            let month = components.month,
            let day = components.day,
            let hour = components.hour,
            let minute = components.minute,
            let second = components.second
        else {
            return ""
        }

        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
    }

    private func fetchDailyReport(executable: String, date: Date) async throws -> WatsonDailyReport {
        let reportsByStartDate = try await fetchReportsByStartDate(
            executable: executable,
            from: date,
            to: date,
            failureFallback: "Unable to read Watson daily log."
        )

        return reportsByStartDate[Calendar.current.startOfDay(for: date)] ?? WatsonDailyReport(entries: [])
    }

    private func fetchReportsByStartDate(
        executable: String,
        from startDate: Date,
        to endDate: Date,
        failureFallback: String
    ) async throws -> [Date: WatsonDailyReport] {
        let result = try await run(
            executable: executable,
            arguments: [
                "log",
                "--from",
                watsonDateString(from: startDate),
                "--to",
                watsonDateString(from: endDate),
                "--current",
                "--json"
            ]
        )

        guard result.exitCode == 0 else {
            throw ServiceError.commandFailed(
                commandFailureMessage(from: result, fallback: failureFallback)
            )
        }

        let frames = try decodeLogFrames(from: cleaned(result.combinedOutput))
        let calendar = Calendar.current
        let groupedFrames = Dictionary(grouping: frames) { frame in
            calendar.startOfDay(for: frame.start)
        }

        return groupedFrames.mapValues { frames in
            WatsonDailyReport(
                entries: frames
                    .sorted { $0.start < $1.start }
                    .map(WatsonDailyEntry.init)
            )
        }
    }

    private func decodeLogFrames(from text: String) throws -> [WatsonLogFrame] {
        guard !text.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateText = try container.decode(String.self)

            if let date = Self.iso8601Date(from: dateText, includingFractionalSeconds: true) {
                return date
            }

            if let date = Self.iso8601Date(from: dateText, includingFractionalSeconds: false) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Watson log date: \(dateText)"
            )
        }

        do {
            return try decoder.decode([WatsonLogFrame].self, from: Data(text.utf8))
        } catch {
            throw ServiceError.commandFailed("Unable to parse Watson log output.")
        }
    }

    private static func iso8601Date(from text: String, includingFractionalSeconds: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = includingFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func run(executable: String, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            let stdin = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = processEnvironment()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin

            process.terminationHandler = { completedProcess in
                _ = process
                defer {
                    completedProcess.terminationHandler = nil
                }

                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

                continuation.resume(
                    returning: CommandResult(
                        exitCode: completedProcess.terminationStatus,
                        stdout: String(decoding: stdoutData, as: UTF8.self),
                        stderr: String(decoding: stderrData, as: UTF8.self)
                    )
                )
            }

            do {
                try process.run()
                stdin.fileHandleForWriting.closeFile()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct CommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combinedOutput: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct WatsonLogFrame: Decodable {
    let start: Date
    let stop: Date
    let project: String
    let tags: [String]
}

private extension WatsonDailyEntry {
    init(_ frame: WatsonLogFrame) {
        let duration = max(0, Int(frame.stop.timeIntervalSince(frame.start).rounded(.down)))
        let tags = frame.tags.isEmpty ? nil : "[\(frame.tags.joined(separator: ", "))]"

        self.init(
            durationInSeconds: duration,
            projectName: frame.project,
            tags: tags
        )
    }
}
