import AppKit
import Combine
import SwiftUI

enum MenuBarMainPage: Hashable {
    case track
    case history
}

@MainActor
final class MenuBarNavigationState: ObservableObject {
    @Published var isShowingSettings = false

    func showSettings() {
        guard !isShowingSettings else {
            return
        }

        isShowingSettings = true
    }

    func hideSettings() {
        guard isShowingSettings else {
            return
        }

        isShowingSettings = false
    }

    func toggleSettings() {
        isShowingSettings.toggle()
    }
}

@main
struct WatsonMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: MenuBarStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = MenuBarStatusItemController()
    }
}

@MainActor
private final class MenuBarStatusItemController: NSObject {
    private let viewModel = MenuBarViewModel()
    private let updateMonitor = HomebrewUpdateMonitor()
    private let navigationState = MenuBarNavigationState()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private var defaultsObserver: NSObjectProtocol?
    private var statusItemRefreshIsScheduled = false

    override init() {
        super.init()
        configurePopover()
        configureStatusItem()
        observeChanges()
        refreshStatusItem()
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                viewModel: viewModel,
                updateMonitor: updateMonitor,
                navigationState: navigationState
            )
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    private func observeChanges() {
        viewModel.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStatusItemRefresh()
            }
            .store(in: &cancellables)

        updateMonitor.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStatusItemRefresh()
            }
            .store(in: &cancellables)

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleStatusItemRefresh()
            }
        }
    }

    private func scheduleStatusItemRefresh() {
        guard !statusItemRefreshIsScheduled else {
            return
        }

        statusItemRefreshIsScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.statusItemRefreshIsScheduled = false
            self.refreshStatusItem()
        }
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        let showProject = storedBool(forKey: AppStorageKeys.showProjectInMenuBar, defaultValue: true)
        let showTimer = storedBool(forKey: AppStorageKeys.showTrackingInMenuBar, defaultValue: true)
        let menuBarTitle = viewModel.menuBarTitle(showProject: showProject, showTimer: showTimer)
        var title = menuBarTitle ?? ""

        if updateMonitor.state.showsMenuBarBadge {
            title = title.isEmpty ? "!" : "\(title) !"
        }

        button.title = title
        button.toolTip = updateMonitor.menuBarHelpText ?? viewModel.menuBarHelpText

        if viewModel.status.state == .idle || menuBarTitle == nil {
            button.image = NSImage(systemSymbolName: viewModel.menuBarSymbolName, accessibilityDescription: nil)
        } else {
            button.image = nil
        }
    }

    private func storedBool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }

        return defaults.bool(forKey: key)
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        if shouldShowContextMenu {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private var shouldShowContextMenu: Bool {
        guard let event = NSApp.currentEvent else {
            return false
        }

        return event.type == .rightMouseUp || event.modifierFlags.contains(.control)
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else {
            return
        }

        updateMonitor.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        DispatchQueue.main.async { [weak self] in
            self?.popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit WatsonMenuBar", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        if let event = NSApp.currentEvent, let button = statusItem.button {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    @objc
    private func openSettingsFromMenu() {
        navigationState.showSettings()
        showPopover()
    }

    @objc
    private func quitFromMenu() {
        NSApp.terminate(nil)
    }
}
