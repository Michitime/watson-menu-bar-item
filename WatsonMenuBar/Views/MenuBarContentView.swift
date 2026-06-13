import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var updateMonitor: HomebrewUpdateMonitor
    @ObservedObject var navigationState: MenuBarNavigationState
    @AppStorage("lastProject") private var project = ""
    @AppStorage("lastTags") private var tags = ""
    @AppStorage(AppStorageKeys.showTrackingInMenuBar) private var showTimerInMenuBar = true
    @AppStorage(AppStorageKeys.showProjectInMenuBar) private var showProjectInMenuBar = true
    @State private var selectedRecentScope: RecentWorkScope = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader

            if navigationState.isShowingSettings {
                settingsPage
            } else {
                primaryTrackingPanel
                recentWorkArea
            }

            if let footerText = viewModel.footerText {
                NoticeRow(
                    title: viewModel.footerIsError ? "Needs attention" : "Status",
                    detail: footerText,
                    systemName: viewModel.footerIsError ? "exclamationmark.triangle.fill" : "info.circle.fill",
                    tint: viewModel.footerIsError ? .red : .secondary
                )
            }
        }
        .padding(14)
        .frame(width: 360)
        .background(.regularMaterial)
        .onAppear(perform: refresh)
    }

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(viewModel.status.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if viewModel.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }

                Text(statusDetailText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let tagsLine = viewModel.status.tagsLine {
                    Text(tagsLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if let elapsed = viewModel.runningElapsedText {
                    Text(elapsed)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    NativeIconButton(
                        systemName: "arrow.clockwise",
                        accessibilityLabel: "Refresh",
                        help: "Refresh Watson status",
                        isEnabled: viewModel.canRefresh,
                        keyEquivalent: "r",
                        modifiers: .command,
                        action: refresh
                    )

                    NativeIconButton(
                        systemName: navigationState.isShowingSettings ? "gearshape.fill" : "gearshape",
                        accessibilityLabel: "Settings",
                        help: "Show settings",
                        isSelected: navigationState.isShowingSettings,
                        keyEquivalent: ",",
                        modifiers: .command
                    ) {
                        navigationState.toggleSettings()
                    }
                }
            }
        }
    }

    private var primaryTrackingPanel: some View {
        NativeGroup {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Track")

                FieldRow(title: "Project", systemName: "folder") {
                    AutocompleteTextField(
                        text: $project,
                        placeholder: "Project name",
                        candidates: viewModel.projectAutocompleteCandidates,
                        isEnabled: viewModel.canEditInputs,
                        completionMode: .wholeField,
                        onSubmit: startTracking
                    )
                }

                NativeSeparator()

                FieldRow(title: "Tags", systemName: "tag") {
                    AutocompleteTextField(
                        text: $tags,
                        placeholder: "feature, review, cli",
                        candidates: viewModel.tagAutocompleteCandidates,
                        isEnabled: viewModel.canEditInputs,
                        completionMode: .delimitedToken,
                        onSubmit: startTracking
                    )
                    .onChange(of: tags) { _, newValue in
                        let normalized = normalizedTagsInput(newValue)
                        if normalized != newValue {
                            tags = normalized
                        }
                    }
                }

                primaryActionButton
            }
        }
    }

    private var primaryActionButton: some View {
        Button(action: primaryAction) {
            Label(primaryActionTitle, systemImage: primaryActionSymbolName)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .tint(viewModel.status.isRunning ? .red : .accentColor)
        .disabled(!canPerformPrimaryAction)
        .accessibilityLabel(primaryActionTitle)
        .help(primaryActionHelp)
    }

    private var recentWorkArea: some View {
        NativeGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    SectionHeader("Recent Work")

                    Spacer(minLength: 8)

                    Picker("Recent Work", selection: $selectedRecentScope) {
                        ForEach(RecentWorkScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 136)
                    .labelsHidden()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch selectedRecentScope {
                        case .today:
                            todayRows
                        case .week:
                            weekRows
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 214)
            }
        }
    }

    @ViewBuilder
    private var todayRows: some View {
        let summaries = viewModel.status.todayReport.summaries

        if summaries.isEmpty {
            EmptyStateRow(text: "No entries recorded today.")
        } else {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                SummaryResumeRow(
                    summary: summary,
                    dateLabel: "Today",
                    isEnabled: viewModel.canStart
                ) {
                    startTracking(summary: summary, date: Date())
                }

                if index < summaries.count - 1 {
                    NativeSeparator()
                }
            }
        }
    }

    @ViewBuilder
    private var weekRows: some View {
        let days = viewModel.status.workWeekReport.days

        if days.isEmpty {
            EmptyStateRow(text: "No work week data available.")
        } else {
            ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                WorkWeekDayGroup(
                    day: day,
                    totalText: workWeekTotalText(for: day.report),
                    canStart: viewModel.canStart,
                    start: startTracking(summary:date:)
                )

                if dayIndex < days.count - 1 {
                    NativeSeparator()
                        .padding(.vertical, 2)
                }
            }
        }
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if updateMonitor.state.showsUpdateNotice {
                    updateNoticeRow
                }

                NativeGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader("Menu Bar")
                            .padding(.bottom, 6)

                        SettingsRow(title: "Show Timer", systemName: "timer") {
                            Toggle("Show Timer", isOn: $showTimerInMenuBar)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        NativeSeparator()

                        SettingsRow(title: "Show Project", systemName: "text.badge.checkmark") {
                            Toggle("Show Project", isOn: $showProjectInMenuBar)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }

                NativeGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader("Automation")
                            .padding(.bottom, 6)

                        SettingsRow(title: "Auto Stop", systemName: "stopwatch") {
                            Toggle("Auto Stop", isOn: autoStopBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        if viewModel.autoStopIsOn {
                            NativeSeparator()

                            SettingsRow(
                                title: "Stop Time",
                                subtitle: viewModel.autoStopStatusText,
                                subtitleIsWarning: viewModel.autoStopStatusIsError,
                                systemName: "clock"
                            ) {
                                DatePicker(
                                    "Stop Time",
                                    selection: autoStopTimeBinding,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .frame(width: 106, alignment: .trailing)
                            }
                        }
                    }
                }

                NativeGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader("App")
                            .padding(.bottom, 6)

                        SettingsRow(
                            title: "Launch at Login",
                            subtitle: viewModel.launchAtLoginStatusText,
                            subtitleIsWarning: viewModel.launchAtLoginNeedsApproval,
                            systemName: "power"
                        ) {
                            HStack(spacing: 8) {
                                if viewModel.launchAtLoginNeedsApproval {
                                    Button("Open") {
                                        viewModel.openLoginItemsSettings()
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .help("Open Login Items settings")
                                }

                                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                        }

                        if let executablePathText = viewModel.executablePathText {
                            NativeSeparator()

                            SettingsRow(
                                title: executablePathText,
                                systemName: "terminal",
                                showsSymbolBackground: false
                            ) {
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 392)
    }

    private var updateNoticeRow: some View {
        NoticeRow(
            title: updateMonitor.state.noticeTitle,
            detail: updateMonitor.state.noticeDetail,
            systemName: updateMonitor.state.symbolName,
            tint: updateNoticeColor,
            actionTitle: updateMonitor.state.actionTitle,
            isActionEnabled: updateMonitor.canRestartToUpdate
        ) {
            updateMonitor.restartToUpdate()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if viewModel.status.isRunning {
            TrackingClockIcon(accentColor: accentColor)
                .frame(width: 30, height: 30)
        } else {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.14))

                Image(systemName: headerSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 30, height: 30)
        }
    }

    private var statusDetailText: String {
        if let primaryLine = viewModel.status.primaryLine {
            return primaryLine
        }

        return viewModel.status.isRunning ? "Tracking" : "Ready"
    }

    private var primaryActionTitle: String {
        viewModel.status.isRunning ? "Stop" : "Start"
    }

    private var primaryActionSymbolName: String {
        viewModel.status.isRunning ? "stop.fill" : "play.fill"
    }

    private var primaryActionHelp: String {
        viewModel.status.isRunning ? "Stop the current Watson frame" : "Start tracking this project"
    }

    private var canPerformPrimaryAction: Bool {
        if viewModel.status.isRunning {
            return viewModel.canStop
        }

        return viewModel.canStart && !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func primaryAction() {
        if viewModel.status.isRunning {
            stopTracking()
        } else {
            startTracking()
        }
    }

    private func normalizedTagsInput(_ text: String) -> String {
        var normalized = ""

        for character in text {
            if character == "," || character == ";" {
                while normalized.last == "-" {
                    normalized.removeLast()
                }

                normalized.append(character)
                normalized.append(" ")
                continue
            }

            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                if let last = normalized.last, last != "-" && last != "," && last != ";" && last != " " {
                    normalized.append("-")
                }
                continue
            }

            normalized.append(character)
        }

        return normalized
    }

    private var updateNoticeColor: Color {
        switch updateMonitor.state {
        case .restartFailed:
            return .red
        case .current, .updatedOnDisk:
            return .orange
        }
    }

    private var accentColor: Color {
        switch viewModel.status.state {
        case .running:
            return .green
        case .idle:
            return .secondary
        case .loading:
            return .blue
        case .unavailable, .error:
            return .red
        }
    }

    private var headerSymbolName: String {
        switch viewModel.status.state {
        case .running:
            return "play.fill"
        case .idle:
            return "pause.fill"
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .unavailable, .error:
            return "exclamationmark"
        }
    }

    private func startTracking() {
        Task {
            await viewModel.start(project: project, tagsInput: tags)
        }
    }

    private func startTracking(summary: WatsonDailySummary, date: Date) {
        project = summary.projectName
        tags = viewModel.tagsInput(for: summary)

        Task {
            await viewModel.start(summary: summary, on: date)
        }
    }

    private func stopTracking() {
        Task {
            await viewModel.stop()
        }
    }

    private func refresh() {
        Task {
            updateMonitor.refresh()
            await viewModel.refresh()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLoginIsOn },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    private var autoStopBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoStopIsOn },
            set: { viewModel.setAutoStop($0) }
        )
    }

    private var autoStopTimeBinding: Binding<Date> {
        Binding(
            get: { viewModel.autoStopTime },
            set: { viewModel.setAutoStopTime($0) }
        )
    }

    private func workWeekTotalText(for report: WatsonDailyReport) -> String {
        guard report.totalDurationInSeconds > 0 else {
            return "No time"
        }

        return WatsonDurationFormatter.displayString(for: report.totalDurationInSeconds)
    }
}

private enum RecentWorkScope: String, CaseIterable, Identifiable {
    case today
    case week

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .week:
            return "Week"
        }
    }
}

private struct NativeGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.38), lineWidth: 1)
            }
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct NativeIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let help: String
    var isEnabled = true
    var isSelected = false
    var keyEquivalent: KeyEquivalent?
    var modifiers: EventModifiers = []
    let action: () -> Void

    var body: some View {
        Group {
            if let keyEquivalent {
                content
                    .keyboardShortcut(keyEquivalent, modifiers: modifiers)
            } else {
                content
            }
        }
    }

    private var content: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct FieldRow<Content: View>: View {
    let title: String
    let systemName: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            content
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleIsWarning = false
    let systemName: String
    var showsSymbolBackground = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                if showsSymbolBackground {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                }

                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleIsWarning ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct NoticeRow: View {
    let title: String
    let detail: String
    let systemName: String
    let tint: Color
    var actionTitle: String?
    var isActionEnabled = true
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!isActionEnabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.38), lineWidth: 1)
        }
    }
}

private struct SummaryResumeRow: View {
    let summary: WatsonDailySummary
    var dateLabel: String?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summary.projectName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        Text(WatsonDurationFormatter.displayString(for: summary.totalDurationInSeconds))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let detailText {
                        Text(detailText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel("Resume \(summary.projectName)")
        .help("Resume \(summary.projectName)")
    }

    private var detailText: String? {
        var parts: [String] = []

        if let dateLabel, !dateLabel.isEmpty {
            parts.append(dateLabel)
        }

        if let formattedTagsText, !formattedTagsText.isEmpty {
            parts.append(formattedTagsText)
        }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: " - ")
    }

    private var formattedTagsText: String? {
        let tags = tagTokens(from: summary.tags)

        guard !tags.isEmpty else {
            return nil
        }

        return tags.map { "#\($0)" }.joined(separator: " ")
    }

    private func tagTokens(from text: String?) -> [String] {
        guard var text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
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
}

private struct WorkWeekDayGroup: View {
    let day: WatsonWorkWeekDayReport
    let totalText: String
    let canStart: Bool
    let start: (WatsonDailySummary, Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day.date, format: .dateTime.weekday(.wide))
                        .font(.system(size: 12, weight: .semibold))

                    Text(day.date, format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(dayTotalLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .separatorColor).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if day.report.summaries.isEmpty {
                EmptyStateRow(text: "No entries recorded.")
                    .padding(.leading, 22)
                    .padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(day.report.summaries.enumerated()), id: \.element.id) { index, summary in
                        SummaryResumeRow(
                            summary: summary,
                            dateLabel: nil,
                            isEnabled: canStart
                        ) {
                            start(summary, day.date)
                        }

                        if index < day.report.summaries.count - 1 {
                            NativeSeparator()
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.top, 4)
            }
        }
    }

    private var dayTotalLabel: String {
        totalText == "No time" ? totalText : "\(totalText) total"
    }
}

private struct EmptyStateRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct NativeSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(height: 1)
    }
}

private struct TrackingClockIcon: View {
    let accentColor: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsedSeconds = context.date.timeIntervalSinceReferenceDate.rounded(.down)
            let angleDegrees = elapsedSeconds * 90

            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))

                Circle()
                    .stroke(accentColor.opacity(0.35), lineWidth: 1)

                ClockHand(angleDegrees: angleDegrees)
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .padding(5)

                Circle()
                    .fill(accentColor)
                    .frame(width: 3, height: 3)
            }
            .animation(.easeInOut(duration: 0.2), value: angleDegrees)
        }
    }
}

private struct ClockHand: Shape {
    var angleDegrees: Double

    var animatableData: Double {
        get { angleDegrees }
        set { angleDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length = min(rect.width, rect.height) * 0.36
        let radians = (angleDegrees - 90) * .pi / 180
        let endPoint = CGPoint(
            x: center.x + (cos(radians) * length),
            y: center.y + (sin(radians) * length)
        )

        var path = Path()
        path.move(to: center)
        path.addLine(to: endPoint)
        return path
    }
}
