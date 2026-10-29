import AppKit
import CloudCore
import ServiceManagement
import SwiftUI

struct NewTunnelSheet: View {
    let store: Store
    /// Called with the new tunnel's id, or nil when cancelled.
    let close: (String?) -> Void

    @State private var folder: URL?
    @State private var name = ""
    @State private var domain = ""
    @State private var origin = ""
    @State private var picking = false
    @State private var error: String?

    var hostname: String? {
        let domain = domain.isEmpty ? store.defaultDomain : domain
        guard !name.isEmpty, let domain else { return nil }
        return "\(Folder.slug(name)).\(domain)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Tunnel").font(.title2.weight(.bold))
                Text("Share a local project on your own domain.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 24)

            Form {
                Section {
                    LabeledContent("Folder") {
                        HStack {
                            Text(folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Optional")
                                .foregroundStyle(folder == nil ? .tertiary : .primary)
                                .lineLimit(1).truncationMode(.head)
                            Button("Choose…") { picking = true }
                        }
                    }
                    TextField("Name", text: $name, prompt: Text("myapp"))
                    TextField("Domain", text: $domain, prompt: Text(store.defaultDomain ?? "example.com"))
                } footer: {
                    Text("Linking a folder lets `tunnel start` and friends work from inside it.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Origin", text: $origin, prompt: Text("myapp.test, localhost:3000 or 8787"))
                } footer: {
                    Text("Where traffic goes on this Mac: a local hostname, a URL, or a port.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)

            VStack(spacing: 14) {
                if let hostname {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text("https://\(hostname)").fontWeight(.medium)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(origin.isEmpty ? "?" : origin).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .glassEffect(.regular, in: .capsule)
                }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if store.linking { ProgressView().controlSize(.small); Text("Creating…").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Cancel") { close(nil) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("Create Tunnel", action: create)
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(hostname == nil || origin.isEmpty || store.linking)
                }
                .controlSize(.large)
            }
            .padding([.horizontal, .bottom], 24)
        }
        .frame(width: 500)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            folder = url
            let slug = Folder.slug(url.lastPathComponent)
            if name.isEmpty { name = slug }
            if origin.isEmpty { origin = "\(slug).\(Settings.load().tld)" }
        }
    }

    func create() {
        error = nil
        do {
            let request = Operations.LinkRequest(
                name: name, domain: domain.isEmpty ? nil : domain, origin: try .parse(origin), directory: folder?.path)
            store.link(request) { result in
                switch result {
                case .success(let id): close(id)
                case .failure(let message): error = message.message
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SettingsSheet: View {
    let store: Store
    let close: () -> Void

    @State private var domain = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmClean = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Settings").font(.title2.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 24)

            Form {
                Section {
                    TextField("Default domain", text: $domain, prompt: Text("example.com"))
                        .onSubmit(save)
                } footer: {
                    Text("New tunnels are published as <name>.\(domain.isEmpty ? "example.com" : domain).")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        }
                }
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remove every tunnel")
                            Text("Deletes all tunnels, DNS records, configs and LaunchAgents. Keeps your Cloudflare login.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clean Up…", role: .destructive) { confirmClean = true }
                            .disabled(!store.hasTunnels || store.cleaning)
                            .confirmationDialog("Remove every tunnel?", isPresented: $confirmClean) {
                                Button("Remove Everything", role: .destructive) { store.cleanAll() }
                            } message: {
                                Text("Every shared URL stops working right away.")
                            }
                    }
                } header: {
                    Text("Fresh start")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)

            HStack {
                if store.cleaning { ProgressView().controlSize(.small); Text("Cleaning up…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", action: close).buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Save", action: save).buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], 24)
        }
        .frame(width: 500)
        .onAppear { domain = store.defaultDomain ?? "" }
    }

    func save() {
        if domain != (store.defaultDomain ?? "") { store.setDefaultDomain(domain) }
        close()
    }
}
