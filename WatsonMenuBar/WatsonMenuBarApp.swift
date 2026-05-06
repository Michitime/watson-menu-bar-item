import SwiftUI

@main
struct WatsonMenuBarApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            Image(systemName: viewModel.menuBarSymbolName)
                .symbolRenderingMode(.monochrome)
            .help(viewModel.menuBarHelpText)
        }
        .menuBarExtraStyle(.window)
    }
}
