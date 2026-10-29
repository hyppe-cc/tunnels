import AppKit
import SwiftUI

@main
struct TunnelsApp: App {
    @State private var store = Store()

    init() { Snapshot.scheduleIfRequested() }

    var body: some Scene {
        Window("Tunnels", id: MainView.windowID) {
            MainView(store: store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 920, height: 600)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Image(systemName: store.anyRunning ? "cloud.fill" : "cloud")
        }
        .menuBarExtraStyle(.window)
    }
}

enum Dock {
    /// Shows the Dock icon while the window is open; the app is menu-bar-only otherwise.
    @MainActor static func show(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        if visible { NSApp.activate() }
    }
}
