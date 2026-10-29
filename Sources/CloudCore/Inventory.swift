import Foundation

public struct SiteRow: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case running(pid: Int32, managed: Bool)
        /// Has a config but nothing runs it.
        case stopped
        case broken(String)

        public var isRunning: Bool { if case .running = self { true } else { false } }
        public var label: String {
            switch self {
            case .running(_, true): "running"
            case .running(_, false): "running (manual)"
            case .stopped: "stopped"
            case .broken(let reason): "broken: \(reason)"
            }
        }
    }

    public let config: TunnelConfig?
    public let tunnel: TunnelInfo?
    /// What `tunnel link` recorded: folder, name and domain.
    public let project: Settings.Project?
    public let title: String
    public let state: State
    public let hasAgent: Bool

    public var id: String { config?.hostname ?? "tunnel:\(tunnel?.id ?? "?")" }
    /// The public hostname, or the tunnel name for a tunnel with no config.
    public var domain: String { config?.hostname ?? tunnel?.name ?? "?" }
    public var name: String { project?.name ?? config.map { String($0.hostname.prefix { $0 != "." }) } ?? domain }
    public var directory: String? { project?.directory }
    public var publicURL: String? { config?.publicURL }
    public var originLabel: String { config?.origin.label ?? "" }
    public var agent: LaunchAgent? { config.map { LaunchAgent(hostname: $0.hostname) } }
    public var isLinked: Bool { config != nil }
}

public struct Inventory: Sendable {
    public let rows: [SiteRow]
    public let warnings: [String]

    public var linkedRows: [SiteRow] { rows.filter(\.isLinked) }
    /// Tunnels in Cloudflare with no config on this Mac.
    public var orphanRows: [SiteRow] { rows.filter { !$0.isLinked } }

    public static func load() -> Inventory {
        let (configs, configErrors) = TunnelConfig.loadAll()
        var warnings = configErrors
        let tunnels: [TunnelInfo]
        do { tunnels = try Cloudflared.list() } catch {
            tunnels = []
            warnings.append("Couldn't list tunnels: \(error.localizedDescription)")
        }
        return build(configs: configs, tunnels: tunnels, settings: .load(), warnings: warnings, probe: true)
    }

    /// `probe: false` skips launchctl/pgrep so tests can build an inventory from fixtures.
    public static func build(configs: [TunnelConfig], tunnels: [TunnelInfo], settings: Settings, warnings: [String] = [], probe: Bool) -> Inventory {
        let tunnelsByID = Dictionary(tunnels.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [SiteRow] = []
        var usedTunnels = Set<String>()

        for config in configs {
            let tunnel = tunnelsByID[config.tunnelID]
            usedTunnels.insert(config.tunnelID)
            let project = settings.projects[config.hostname]
            let agent = LaunchAgent(hostname: config.hostname)

            let state: SiteRow.State
            if probe, let pid = agent.runningPID() {
                state = .running(pid: pid, managed: true)
            } else if probe, let pid = Cloudflared.pids(forConfig: config.path).first {
                state = .running(pid: pid, managed: false)
            } else if !tunnels.isEmpty && tunnel == nil {
                state = .broken("tunnel \(config.tunnelID.prefix(8)) no longer exists")
            } else if config.hostname.hasSuffix(".\(settings.tld)") {
                state = .broken("\(config.hostname) isn't a public hostname")
            } else {
                state = .stopped
            }
            let name = project?.name ?? String(config.hostname.prefix { $0 != "." })
            let title = project?.directory.flatMap(Folder.title(in:)) ?? name
            rows.append(SiteRow(config: config, tunnel: tunnel, project: project, title: title, state: state,
                                hasAgent: probe && agent.isInstalled))
        }

        for tunnel in tunnels where !usedTunnels.contains(tunnel.id) {
            rows.append(SiteRow(config: nil, tunnel: tunnel, project: nil, title: "", state: .broken("no config file"), hasAgent: false))
        }

        rows.sort { a, b in a.isLinked != b.isLinked ? a.isLinked : a.domain < b.domain }
        return Inventory(rows: rows, warnings: warnings)
    }

    /// Finds a row by name (`api`), hostname or tunnel name.
    public func find(_ query: String) -> SiteRow? {
        let q = query.lowercased()
        return rows.first { $0.config?.hostname == q }
            ?? rows.first { $0.isLinked && $0.name == q }
            ?? rows.first { $0.tunnel?.name == q }
            ?? rows.first { $0.config?.hostname.hasPrefix(q + ".") == true }
    }

    /// The row linked from `directory` or a folder above it.
    public func row(forDirectory directory: String, settings: Settings = .load()) -> SiteRow? {
        guard let (hostname, _) = settings.project(containing: directory) else { return nil }
        return rows.first { $0.config?.hostname == hostname }
    }
}
