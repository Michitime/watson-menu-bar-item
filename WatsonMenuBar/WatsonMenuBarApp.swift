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

            HStack(spacing: 4) {
                if let menuBarTitle {
                    Text(menuBarTitle)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                } else {
                    Image(systemName: viewModel.menuBarSymbolName)
                        .symbolRenderingMode(.monochrome)
                }
            }
            .help(viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }
}
