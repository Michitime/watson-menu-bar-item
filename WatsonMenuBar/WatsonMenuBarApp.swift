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
            HStack(spacing: 4) {
                Image(systemName: viewModel.menuBarSymbolName)
                    .symbolRenderingMode(.monochrome)

                if let menuBarTitle = viewModel.menuBarTitle(
                    showProject: showProjectInMenuBar,
                    showTimer: showTimerInMenuBar
                ) {
                    Text(menuBarTitle)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
            .help(viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }
}
