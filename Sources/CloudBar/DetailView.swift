import AppKit
import CloudCore
import SwiftUI

struct DetailView: View {
    let row: SiteRow
    let store: Store
    @State private var editing = false
    @State private var newName = ""
    @State private var newDomain = ""
    @State private var confirmDelete = false
    @State private var copied = false
    @State private var log = ""

    var busy: Bool { store.busy.contains(row.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                actions
                if editing { renameCard }
                cards
                if row.isLinked { logCard }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .task(id: store.inventory?.rows.first { $0.id == row.id }) { log = readLog() }
        .confirmationDialog("Delete \(row.domain)?", isPresented: $confirmDelete) {
            Button("Delete Tunnel", role: .destructive) { store.deleteTunnel(row) }
        } message: {
            Text("Stops it and deletes the tunnel and its DNS record in Cloudflare. The URL stops working.")
        }
    }

    // MARK: Header

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(row.domain)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .textSelection(.enabled)
                if !row.title.isEmpty && row.title != row.name {
                    Text(row.title).font(.title3).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            StatusPill(state: row.state)
        }
    }

    // MARK: Actions

    var actions: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if row.isLinked {
                    if case .running(_, false) = row.state {
                        Button("Adopt", systemImage: "arrow.down.circle") { store.adopt(row) }
                            .buttonStyle(.glassProminent)
                            .help("Started by hand; hand it to launchd so it survives reboots")
                    } else {
                        Button(row.state.isRunning ? "Stop" : "Start",
                               systemImage: row.state.isRunning ? "stop.fill" : "play.fill") { store.toggle(row) }
                            .buttonStyle(.glassProminent)
                            .tint(row.state.isRunning ? .red : .green)
                    }
                    if let url = row.publicURL {
                        Button("Open", systemImage: "safari") { NSWorkspace.shared.open(URL(string: url)!) }
                            .buttonStyle(.glass)
                        Button(copied ? "Copied" : "Copy URL", systemImage: copied ? "checkmark" : "link") {
                            Clipboard.copy(url)
                            withAnimation { copied = true }
                            Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation { copied = false } }
                        }
                        .buttonStyle(.glass)
                    }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Menu {
                    if row.isLinked {
                        Button("Change Name or Domain…", systemImage: "pencil") { startEditing() }
                        Button("Restart", systemImage: "arrow.clockwise") { store.perform(row) { try Operations.restart($0) } }
                        if let dir = row.directory {
                            Button("Show Folder", systemImage: "folder") { NSWorkspace.shared.open(URL(fileURLWithPath: dir)) }
                        }
                        if let agent = row.agent {
                            Button("Show Log", systemImage: "doc.text") { NSWorkspace.shared.open(URL(fileURLWithPath: agent.logPath)) }
                        }
                        Divider()
                    }
                    Button("Delete Tunnel…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .fixedSize()
            }
            .controlSize(.large)
            .disabled(busy)
        }
    }

    // MARK: Rename

    var renameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change name or domain").font(.headline)
            HStack(spacing: 6) {
                TextField("name", text: $newName).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                Text(".").foregroundStyle(.secondary)
                TextField("domain", text: $newDomain).textFieldStyle(.roundedBorder)
            }
            Text("Creates https://\(Folder.slug(newName)).\(newDomain) and deletes the old tunnel and DNS record.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { withAnimation { editing = false } }
                    .buttonStyle(.glass)
                Button("Save") {
                    withAnimation { editing = false }
                    store.rename(row, name: newName, domain: newDomain)
                }
                .buttonStyle(.glassProminent)
                .disabled(newName.isEmpty || newDomain.isEmpty)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .transition(.blurReplace)
    }

    func startEditing() {
        newName = row.name
        newDomain = row.currentDomain
        withAnimation(.smooth) { editing = true }
    }

    // MARK: Cards

    var cards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
            if case .broken(let reason) = row.state {
                InfoCard(title: "Problem", icon: "exclamationmark.triangle") { Text(reason).foregroundStyle(.orange) }
            }
            if row.isLinked {
                InfoCard(title: "Origin", icon: "arrow.right.circle") { Text(row.config?.service ?? row.originLabel) }
                InfoCard(title: "Folder", icon: "folder") {
                    Text(row.directory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Not linked to a folder")
                        .foregroundStyle(row.directory == nil ? .secondary : .primary)
                        .truncationMode(.head)
                }
            }
            InfoCard(title: "Edge", icon: "antenna.radiowaves.left.and.right") {
                Text(row.colos ?? "Not connected").foregroundStyle(row.colos == nil ? .secondary : .primary)
            }
            InfoCard(title: "Tunnel", icon: "point.3.connected.trianglepath.dotted") {
                Text(row.tunnel?.name ?? row.config?.tunnelID ?? "—")
                    .font(.callout.monospaced())
            }
        }
    }

    var logCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Log", systemImage: "text.alignleft").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let agent = row.agent {
                    Button("Open in Console") { NSWorkspace.shared.open(URL(fileURLWithPath: agent.logPath)) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            ScrollView {
                Text(log.isEmpty ? "No output yet." : log)
                    .font(.caption.monospaced())
                    .foregroundStyle(log.isEmpty ? .tertiary : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .frame(height: 170)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    func readLog() -> String {
        guard let path = row.agent?.logPath,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(60).joined(separator: "\n")
    }
}
