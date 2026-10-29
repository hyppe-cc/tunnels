import AppKit

/// Debug aid: with TUNNELS_SNAPSHOT=<dir>, writes a PNG of each visible window after launch.
/// Renders the app's own views, so it needs no screen-recording permission.
enum Snapshot {
    @MainActor static func scheduleIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["TUNNELS_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            for (index, window) in NSApp.windows.enumerated() where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = window.title.isEmpty ? "window-\(index)" : window.title
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
    }
}
