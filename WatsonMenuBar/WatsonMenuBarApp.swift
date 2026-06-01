import SwiftUI

@main
struct WatsonMenuBarApp: App {
    @StateObject private var viewModel = MenuBarViewModel()
    @AppStorage(AppStorageKeys.showTrackingInMenuBar) private var showTimerInMenuBar = true
    @AppStorage(AppStorageKeys.showProjectInMenuBar) private var showProjectInMenuBar = true

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
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
            }
            .help(viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }
}
