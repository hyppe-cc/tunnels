import AppKit
import CloudCore
import SwiftUI

/// The menu bar popover: status, run/stop, open the app, quit. Everything else lives in the window.
struct MenuBarView: View {
    let store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tunnels").font(.headline)
                Spacer()
                if let inventory = store.inventory {
                    let running = inventory.linkedRows.filter(\.state.isRunning).count
                    Text("\(running) of \(inventory.linkedRows.count) running")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            VStack(spacing: 2) {
                if let rows = store.inventory?.linkedRows {
                    if rows.isEmpty {
                        Text("No tunnels yet")
                            .font(.callout).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                    }
                    ForEach(rows) { MenuRow(row: $0, store: store) }
                } else {
                    ProgressView().controlSize(.small).padding(.vertical, 18)
                }
            }
            .padding(.horizontal, 6)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        openWindow(id: MainView.windowID)
                        Dock.show(true)
                    } label: {
                        Label("Open Tunnels", systemImage: "macwindow").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button { NSApp.terminate(nil) } label: {
                        Image(systemName: "power")
                    }
                    .buttonStyle(.glass)
                    .help("Quit")
                }
            }
            .controlSize(.large)
            .padding(12)
        }
        .frame(width: 320)
    }
}

private struct MenuRow: View {
    let row: SiteRow
    let store: Store
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(state: row.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.domain).font(.callout.weight(.medium)).lineLimit(1)
                Text(row.state.shortLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if store.busy.contains(row.id) {
                ProgressView().controlSize(.small)
            } else if case .broken = row.state {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Toggle("", isOn: Binding(get: { row.state.isRunning }, set: { _ in store.toggle(row) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if let url = row.publicURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        }
        .help(row.publicURL.map { "Open \($0)" } ?? "")
    }
}
