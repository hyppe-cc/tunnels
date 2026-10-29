import AppKit
import CloudCore
import SwiftUI

struct MainView: View {
    static let windowID = "main"

    let store: Store
    @State private var selection: String?
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case newTunnel, settings
        var id: String { rawValue }
    }

    var rows: [SiteRow] { store.inventory?.rows ?? [] }
    var selected: SiteRow? { rows.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
                .toolbar {
                    ToolbarItem {
                        Button("New Tunnel", systemImage: "plus") { sheet = .newTunnel }
                            .help("Share a local project on your domain")
                    }
                }
        } detail: {
            Group {
                if let row = selected {
                    DetailView(row: row, store: store)
                        .id(row.id)
                } else if store.inventory != nil {
                    EmptyState(hasDomain: store.defaultDomain != nil) {
                        sheet = store.defaultDomain == nil ? .settings : .newTunnel
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItemGroup {
                    Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
                    Button("Settings", systemImage: "gearshape") { sheet = .settings }
                }
            }
        }
        .containerBackground(.ultraThinMaterial, for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .safeAreaInset(edge: .bottom) {
            if let error = store.error { ErrorBanner(message: error) { store.error = nil } }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newTunnel:
                NewTunnelSheet(store: store) { created in
                    self.sheet = nil
                    if let created { selection = created }
                }
            case .settings:
                SettingsSheet(store: store) { self.sheet = nil }
            }
        }
        .onChange(of: store.inventory?.rows.map(\.id)) { _, ids in
            // Keep a selection when there's something to show, and drop one whose tunnel is gone.
            if let ids, selection == nil || !ids.contains(selection!) { selection = ids.first }
        }
        .onAppear {
            Dock.show(true)
            if selection == nil { selection = rows.first?.id }
            // Debug aid for Snapshot: open a sheet at launch.
            if let name = ProcessInfo.processInfo.environment["TUNNELS_SNAPSHOT_SHEET"] { sheet = Sheet(rawValue: name) }
        }
        .onDisappear { Dock.show(false) }
    }
}

private struct Sidebar: View {
    let store: Store
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            if let inventory = store.inventory {
                Section("Tunnels") {
                    ForEach(inventory.linkedRows) { SidebarRow(row: $0, busy: store.busy.contains($0.id)) }
                }
                if !inventory.orphanRows.isEmpty {
                    Section("Only in Cloudflare") {
                        ForEach(inventory.orphanRows) { SidebarRow(row: $0, busy: store.busy.contains($0.id)) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let domain = store.defaultDomain {
                Label(domain, systemImage: "globe")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 12)
            }
        }
    }
}

private struct SidebarRow: View {
    let row: SiteRow
    let busy: Bool

    var body: some View {
        HStack(spacing: 10) {
            if busy {
                ProgressView().controlSize(.mini).frame(width: 8)
            } else {
                StatusDot(state: row.state)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.domain).font(.body.weight(.medium)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .tag(row.id)
    }

    var subtitle: String {
        if !row.title.isEmpty && row.title != row.name { return row.title }
        return row.isLinked ? "→ \(row.originLabel)" : "No config on this Mac"
    }
}

private struct EmptyState: View {
    let hasDomain: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cloud")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.breathe)
            VStack(spacing: 6) {
                Text(hasDomain ? "No tunnels yet" : "Pick a domain").font(.title2.weight(.semibold))
                Text(hasDomain
                     ? "Share a local project on your domain, or run `tunnel link` in its folder."
                     : "Tunnels are published as <name>.<your domain>.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(hasDomain ? "New Tunnel" : "Set Default Domain", action: action)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(40)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(14)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 16))
        .padding(16)
    }
}
