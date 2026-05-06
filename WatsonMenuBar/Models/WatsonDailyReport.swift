import Foundation

struct WatsonDailyReport: Equatable {
    let entries: [WatsonDailyEntry]

    var summaries: [WatsonDailySummary] {
        var orderedKeys: [WatsonDailySummary.Key] = []
        var totalsByKey: [WatsonDailySummary.Key: Int] = [:]

        for entry in entries {
            let key = WatsonDailySummary.Key(projectName: entry.projectName, tags: entry.tags)
            if totalsByKey[key] == nil {
                orderedKeys.append(key)
            }
            totalsByKey[key, default: 0] += entry.durationInSeconds
        }

        return orderedKeys.compactMap { key in
            guard let totalDuration = totalsByKey[key] else {
                return nil
            }

            return WatsonDailySummary(
                projectName: key.projectName,
                tags: key.tags,
                totalDurationInSeconds: totalDuration
            )
        }
    }
}

struct WatsonDailyEntry: Equatable {
    let durationInSeconds: Int
    let projectName: String
    let tags: String?
}

struct WatsonDailySummary: Equatable, Identifiable {
    struct Key: Hashable {
        let projectName: String
        let tags: String?
    }

    let projectName: String
    let tags: String?
    let totalDurationInSeconds: Int

    var id: String {
        "\(projectName)|\(tags ?? "")"
    }

    var displayText: String {
        if let tags, !tags.isEmpty {
            return "\(projectName) \(tags) \(WatsonDurationFormatter.displayString(for: totalDurationInSeconds))"
        }

        return "\(projectName) \(WatsonDurationFormatter.displayString(for: totalDurationInSeconds))"
    }
}

enum WatsonDurationFormatter {
    static func displayString(for totalSeconds: Int) -> String {
        if totalSeconds < 60 {
            return "\(totalSeconds) \(totalSeconds == 1 ? "second" : "seconds")"
        }

        let minutes = totalSeconds / 60
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}
