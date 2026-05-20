import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @AppStorage("lastProject") private var project = ""
    @AppStorage("lastTags") private var tags = ""
    @AppStorage("workWeekExpanded") private var workWeekExpanded = true
    @AppStorage(AppStorageKeys.showTrackingInMenuBar) private var showTimerInMenuBar = true
    @AppStorage(AppStorageKeys.showProjectInMenuBar) private var showProjectInMenuBar = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader
            Divider()
            inputSection
            actionRow
            todayLogSection
            workWeekSection

            Divider()

            settingsSection

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit WatsonMenuBar", systemImage: "power")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            if let footerText = viewModel.footerText {
                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(viewModel.footerIsError ? Color.red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var statusHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.16))

                Image(systemName: headerSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            .frame(width: 30, height: 30)

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

            if viewModel.status.isRunning, let elapsed = viewModel.status.elapsed {
                Text(elapsed)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Project name", text: $project)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.canEditInputs)
                    .onSubmit(startTracking)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("feature, review, cli", text: $tags)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.canEditInputs)
                    .onChange(of: tags) { newValue in
                        let normalized = normalizedTagsInput(newValue)
                        if normalized != newValue {
                            tags = normalized
                        }
                    }
                    .onSubmit(startTracking)
            }

            Text("Separate tags with commas or semicolons.\nSpaces become hyphens.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                continue
            }

            if character.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                if let last = normalized.last, last != "-" && last != "," && last != ";" {
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

            Button("Refresh", action: refresh)
                .buttonStyle(.bordered)
                .disabled(!viewModel.canRefresh)
        }
    }

    @ViewBuilder
    private var todayLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if !viewModel.status.todayReport.summaries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.status.todayReport.summaries) { summary in
                            Text(summary.displayText)
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    Text("No entries recorded today.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var workWeekSection: some View {
        DisclosureGroup(isExpanded: $workWeekExpanded) {
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
            .padding(.top, 8)
        } label: {
            Label("Week", systemImage: "list.bullet")
                .font(.system(size: 12, weight: .semibold))
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
                        Text(summary.displayText)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func stopTracking() {
        Task {
            await viewModel.stop()
        }
    }

    private func refresh() {
        Task {
            await viewModel.refresh()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { viewModel.launchAtLoginIsOn },
            set: { viewModel.setLaunchAtLogin($0) }
        )
    }

    private func workWeekTotalText(for report: WatsonDailyReport) -> String {
        guard report.totalDurationInSeconds > 0 else {
            return "No time"
        }

        return WatsonDurationFormatter.displayString(for: report.totalDurationInSeconds)
    }
}
