import Foundation

struct WatsonDailyReportParser {
    private let entryRegex = try? NSRegularExpression(
        pattern: #"^\s*\S+\s+\d{2}:\d{2}\s+to\s+\d{2}:\d{2}\s+(.+?)\s{2,}(.+?)(?:\s{2,}(\[[^\]]+\]))?\s*$"#
    )
    private let hourRegex = try? NSRegularExpression(pattern: #"(\d+)h"#)
    private let minuteRegex = try? NSRegularExpression(pattern: #"(\d+)m"#)
    private let secondRegex = try? NSRegularExpression(pattern: #"(\d+)s"#)

    func parse(_ rawReport: String) -> WatsonDailyReport {
        let lines = rawReport
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard lines.count > 1 else {
            return WatsonDailyReport(entries: [])
        }

        let entries = lines
            .dropFirst()
            .compactMap(parseEntry(from:))

        return WatsonDailyReport(entries: entries)
    }

    private func parseEntry(from line: String) -> WatsonDailyEntry? {
        guard
            let regex = entryRegex,
            let match = firstMatch(in: line, regex: regex),
            let durationText = capture(in: line, match: match, at: 1),
            let projectName = capture(in: line, match: match, at: 2)?.trimmingCharacters(in: .whitespaces)
        else {
            return nil
        }

        let tags = capture(in: line, match: match, at: 3)

        guard !projectName.isEmpty, let durationInSeconds = parseDuration(durationText) else {
            return nil
        }

        return WatsonDailyEntry(
            durationInSeconds: durationInSeconds,
            projectName: projectName,
            tags: tags
        )
    }

    private func parseDuration(_ text: String) -> Int? {
        let hours = value(in: text, regex: hourRegex) ?? 0
        let minutes = value(in: text, regex: minuteRegex) ?? 0
        let seconds = value(in: text, regex: secondRegex) ?? 0
        let totalSeconds = (hours * 3600) + (minutes * 60) + seconds

        return totalSeconds > 0 ? totalSeconds : nil
    }

    private func value(in text: String, regex: NSRegularExpression?) -> Int? {
        guard
            let regex,
            let match = firstMatch(in: text, regex: regex),
            let capturedValue = capture(in: text, match: match, at: 1)
        else {
            return nil
        }

        return Int(capturedValue)
    }

    private func firstMatch(in text: String, regex: NSRegularExpression) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range)
    }

    private func capture(in text: String, match: NSTextCheckingResult, at index: Int) -> String? {
        guard
            index < match.numberOfRanges,
            let range = Range(match.range(at: index), in: text)
        else {
            return nil
        }

        return String(text[range])
    }
}
