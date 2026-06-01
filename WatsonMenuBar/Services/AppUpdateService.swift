import Foundation
import Sparkle

@MainActor
final class AppUpdateService: NSObject, ObservableObject {
    @Published private(set) var state: AppUpdateState
    @Published private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?
    private var pendingInstallHandler: (() -> Void)?
    private var pendingVersion: String?

    override init() {
        state = Self.hasConfiguredUpdates ? .idle : .notConfigured
        super.init()

        guard Self.hasConfiguredUpdates else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        updaterController = controller
        observeCanCheckForUpdates(on: controller.updater)
        controller.startUpdater()
    }

    var isConfigured: Bool {
        updaterController != nil
    }

    var showsUpdateNotice: Bool {
        state.noticeTitle != nil
    }

    var showsManualCheckAction: Bool {
        isConfigured && !showsUpdateNotice
    }

    var canPerformPrimaryAction: Bool {
        guard isConfigured else {
            return false
        }

        switch state {
        case .available, .downloaded, .readyToRestart, .error:
            return canCheckForUpdates || pendingInstallHandler != nil
        case .notConfigured, .idle, .checking, .downloading, .installing:
            return false
        }
    }

    var menuBarHelpText: String? {
        switch state {
        case .available(let version):
            return "WatsonMenuBar \(version) is available."
        case .downloading(let version):
            return "WatsonMenuBar \(version) is downloading."
        case .downloaded(let version), .readyToRestart(let version):
            return "WatsonMenuBar \(version) is ready to install."
        case .installing:
            return "WatsonMenuBar is installing an update."
        case .error(let message):
            return "WatsonMenuBar update check failed: \(message)"
        case .notConfigured, .idle, .checking:
            return nil
        }
    }

    func checkForUpdates() {
        guard let updater = updaterController?.updater, updater.canCheckForUpdates else {
            return
        }

        state = .checking
        updater.checkForUpdates()
    }

    func performPrimaryAction() {
        switch state {
        case .readyToRestart, .downloaded:
            if let pendingInstallHandler {
                state = .installing(version: pendingVersion)
                self.pendingInstallHandler = nil
                pendingInstallHandler()
            } else {
                checkForUpdates()
            }
        case .available, .error:
            checkForUpdates()
        case .notConfigured, .idle, .checking, .downloading, .installing:
            break
        }
    }

    private static var hasConfiguredUpdates: Bool {
        let feedURL = configuredInfoValue(forKey: "SUFeedURL")
        let publicKey = configuredInfoValue(forKey: "SUPublicEDKey")
        return feedURL != nil && publicKey != nil
    }

    private static func configuredInfoValue(forKey key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedValue.isEmpty, !trimmedValue.contains("$(") else {
            return nil
        }

        return trimmedValue
    }

    private func observeCanCheckForUpdates(on updater: SPUUpdater) {
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheckForUpdates = updater.canCheckForUpdates

            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = canCheckForUpdates
            }
        }
    }

    private func versionText(from item: SUAppcastItem) -> String {
        item.displayVersionString
    }

    private func isNonFailureSparkleError(_ error: any Error) -> Bool {
        let nsError = error as NSError

        guard nsError.domain == SUSparkleErrorDomain else {
            return false
        }

        return nsError.code == 1001 || nsError.code == 4007
    }
}

extension AppUpdateService: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = versionText(from: item)
        pendingVersion = version
        state = .available(version: version)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        pendingVersion = nil
        pendingInstallHandler = nil
        state = .idle
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        let version = versionText(from: item)
        pendingVersion = version
        state = .downloading(version: version)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        let version = versionText(from: item)
        pendingVersion = version
        state = .downloaded(version: version)
    }

    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        let version = versionText(from: item)
        pendingVersion = version
        state = .downloaded(version: version)
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        let version = versionText(from: item)
        pendingVersion = version
        pendingInstallHandler = installHandler
        state = .readyToRestart(version: version)
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        state = .installing(version: pendingVersion)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        pendingInstallHandler = nil
        state = isNonFailureSparkleError(error) ? .idle : .error(error.localizedDescription)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        if let error {
            state = isNonFailureSparkleError(error) ? .idle : .error(error.localizedDescription)
        } else if case .checking = state {
            state = .idle
        }
    }
}
