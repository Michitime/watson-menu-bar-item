import SwiftUI

@main
struct WatsonMenuBarApp: App {
    @StateObject private var viewModel = MenuBarViewModel()
    @StateObject private var updateService = AppUpdateService()
    @AppStorage(AppStorageKeys.showTrackingInMenuBar) private var showTimerInMenuBar = true
    @AppStorage(AppStorageKeys.showProjectInMenuBar) private var showProjectInMenuBar = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel, updateService: updateService)
        } label: {
            let menuBarTitle = viewModel.menuBarTitle(
                showProject: showProjectInMenuBar,
                showTimer: showTimerInMenuBar
            )
            let shouldShowIcon = viewModel.status.state == .idle || menuBarTitle == nil

            HStack(spacing: 4) {
                if shouldShowIcon {
                    Image(systemName: viewModel.menuBarSymbolName)
                        .symbolRenderingMode(.monochrome)
                }

                if let menuBarTitle {
                    Text(menuBarTitle)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }

                if updateService.state.showsMenuBarBadge {
                    Image(systemName: "arrow.down.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.orange)
                }
            }
            .help(updateService.menuBarHelpText ?? viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }
}
