import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @ObservedObject var updateMonitor: HomebrewUpdateMonitor
    @ObservedObject var navigationState: MenuBarNavigationState
    @AppStorage("lastProject") private var project = ""
    @AppStorage("lastTags") private var tags = ""
    @AppStorage(AppStorageKeys.showTrackingInMenuBar) private var showTimerInMenuBar = true
    @AppStorage(AppStorageKeys.showProjectInMenuBar) private var showProjectInMenuBar = true
    @State private var selectedMainPage: MenuBarMainPage = .track

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusHeader
            Divider()
            navigationHeader
            pageContent

            if let footerText = viewModel.footerText {
                Divider()

                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(viewModel.footerIsError ? Color.red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear(perform: refresh)
    }

    private var navigationHeader: some View {
        HStack(spacing: 8) {
            if navigationState.isShowingSettings {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12, weight: .semibold))

                Spacer(minLength: 8)

                Button {
                    navigationState.hideSettings()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close settings")
                .accessibilityLabel("Close settings")
            } else {
                Picker("Section", selection: $selectedMainPage) {
                    Text("Track").tag(MenuBarMainPage.track)
                    Text("Week").tag(MenuBarMainPage.history)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        if navigationState.isShowingSettings {
            scrollablePage(settingsPage)
        } else {
            switch selectedMainPage {
            case .track:
                trackPage
            case .history:
                scrollablePage(historyPage)
            }
        }
    }

    private func scrollablePage(_ content: some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 380)
    }

    private var trackPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputSection

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    todayLogSection
                    yesterdayLogSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 220)
        }
    }

    private var historyPage: some View {
        workWeekHistorySection
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRefresh)

            settingsSection

            if updateMonitor.state.showsUpdateNotice {
                updateNoticeSection
            }
        }
    }

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(viewModel.status.displayTitle)
                        .font(.system(size: 13, weight: .semibold))

                    if viewModel.isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                    }
                }

                if let primaryLine = viewModel.status.primaryLine {
                    Text(primaryLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let tagsLine = viewModel.status.tagsLine {
                    Text(tagsLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let elapsed = viewModel.runningElapsedText {
                Text(elapsed)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    .fill(accentColor.opacity(0.16))

                Image(systemName: headerSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 30, height: 30)
        }
    }

    private var updateNoticeSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: updateMonitor.state.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(updateNoticeColor)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(updateMonitor.state.noticeTitle)
                    .font(.system(size: 12, weight: .semibold))

                Text(updateMonitor.state.noticeDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let actionTitle = updateMonitor.state.actionTitle {
                Button(actionTitle) {
                    updateMonitor.restartToUpdate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!updateMonitor.canRestartToUpdate)
            }
        }
        .padding(10)
        .background(updateNoticeColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AutocompleteTextField(
                    text: $project,
                    placeholder: "Project name",
                    candidates: viewModel.projectAutocompleteCandidates,
                    isEnabled: viewModel.canEditInputs,
                    completionMode: .wholeField,
                    onSubmit: startTracking
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AutocompleteTextField(
                    text: $tags,
                    placeholder: "feature, review, cli",
                    candidates: viewModel.tagAutocompleteCandidates,
                    isEnabled: viewModel.canEditInputs,
                    completionMode: .delimitedToken,
                    onSubmit: startTracking
                )
                    .onChange(of: tags) { newValue in
                        let normalized = normalizedTagsInput(newValue)
                        if normalized != newValue {
                            tags = normalized
                        }
                    }
            }

            Text("Separate tags with commas or semicolons.\nSpaces become hyphens.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            actionRow
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

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Start", action: startTracking)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canStart || project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Stop", action: stopTracking)
                .buttonStyle(.bordered)
                .disabled(!viewModel.canStop)

            Spacer()

            Button("Settings") {
                navigationState.toggleSettings()
            }
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var todayLogSection: some View {
        dailyLogSection(
            title: "Today",
            report: viewModel.status.todayReport,
            date: Date(),
            emptyText: "No entries recorded today."
        )
    }

    @ViewBuilder
    private var yesterdayLogSection: some View {
        dailyLogSection(
            title: "Yesterday",
            report: viewModel.status.yesterdayReport,
            date: yesterdayDate,
            emptyText: "No entries recorded yesterday."
        )
    }

    private func dailyLogSection(
        title: String,
        report: WatsonDailyReport,
        date: Date,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            dailyLogCard(report: report, date: date, emptyText: emptyText)
        }
    }

    private func dailyLogCard(
        report: WatsonDailyReport,
        date: Date,
        emptyText: String
    ) -> some View {
        Group {
            if !report.summaries.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.summaries) { summary in
                            summaryResumeButton(summary, date: date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 116)
            } else {
                Text(emptyText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var workWeekHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.status.workWeekReport.days.isEmpty {
                Text("No work week data available.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(viewModel.status.workWeekReport.days) { day in
                    workWeekDay(day)

                    if day.id != viewModel.status.workWeekReport.days.last?.id {
                        workWeekDaySeparator
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func workWeekDay(_ day: WatsonWorkWeekDayReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(day.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .semibold))

                Text(day.date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(workWeekTotalText(for: day.report))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !day.report.summaries.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(day.report.summaries) { summary in
                        summaryResumeButton(summary, date: day.date)
                    }
                }
            } else {
                Text("No entries recorded.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func summaryResumeButton(_ summary: WatsonDailySummary, date: Date) -> some View {
        Button {
            startTracking(summary: summary, date: date)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(summary.displayText)
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canStart)
        .opacity(viewModel.canStart ? 1 : 0.45)
        .accessibilityLabel("Start \(summary.displayText)")
        .help("Start \(summary.projectName)")
    }

    private var workWeekDaySeparator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Show Timer in Menu Bar")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("Show Timer in Menu Bar", isOn: $showTimerInMenuBar)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Text("Show Project in Menu Bar")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("Show Project in Menu Bar", isOn: $showProjectInMenuBar)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Text("Auto Stop")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("Auto Stop", isOn: autoStopBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity)

            if viewModel.autoStopIsOn {
                HStack(spacing: 12) {
                    Text("Stop Time")
                        .font(.system(size: 12, weight: .medium))

                    Spacer()

                    DatePicker("Stop Time", selection: autoStopTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .controlSize(.regular)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 108, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)

                if let statusText = viewModel.autoStopStatusText {
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(viewModel.autoStopStatusIsError ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Text("Launch at Login")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .frame(maxWidth: .infinity)

            if let statusText = viewModel.launchAtLoginStatusText {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(viewModel.launchAtLoginNeedsApproval ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.launchAtLoginNeedsApproval {
                        Button("Open Login Items") {
                            viewModel.openLoginItemsSettings()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }

            if let executablePathText = viewModel.executablePathText {
                Text(executablePathText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

    private var yesterdayDate: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
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
