import Foundation

/// The actions shared by the CLI and the menu bar app.
public enum Operations {
    /// What to publish: `<name>.<domain>` → origin, optionally remembered against a folder.
    public struct LinkRequest: Sendable {
        public var name: String
        /// nil uses the default domain.
        public var domain: String?
        public var origin: OriginSpec
        public var directory: String?

        public init(name: String, domain: String? = nil, origin: OriginSpec, directory: String? = nil) {
            self.name = name
            self.domain = domain
            self.origin = origin
            self.directory = directory
        }
    }

    /// The origin a folder most likely serves at: `https://<folder>.<tld>`, falling back to http.
    /// Returns nil when neither answers, so the caller can ask for --origin or --port.
    public static func guessOrigin(forFolder name: String, settings: Settings = .load()) -> OriginSpec? {
        let host = "\(Folder.slug(name)).\(settings.tld)"
        for scheme in ["https", "http"] {
            let url = "\(scheme)://\(host)"
            let code = Shell.run("curl", ["-sk", "-o", "/dev/null", "--max-time", "3", "-w", "%{http_code}", url]).stdout
            if let status = Int(code), status > 0 { return try? .parse(url) }
        }
        return nil
    }

    /// Creates the tunnel, routes DNS, writes the config and the LaunchAgent, and records the folder.
    /// Every step reuses what already exists. If the folder was linked under another hostname
    /// (a name or domain change), that tunnel and its DNS record are removed first.
    @discardableResult
    public static func link(_ request: LinkRequest, start: Bool = true, log: (String) -> Void = { _ in }) throws -> TunnelConfig {
        let settings = Settings.load()
        let name = Folder.slug(request.name)
        guard !name.isEmpty else { throw CloudError("Name can't be empty") }
        let domain = try request.domain.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) } ?? settings.requireDomain()
        let hostname = "\(name).\(domain)"

        if let directory = request.directory, let (oldHost, _) = settings.project(containing: directory), oldHost != hostname,
           settings.projects[oldHost]?.directory == directory,
           let old = Inventory.load().rows.first(where: { $0.config?.hostname == oldHost }) {
            log("Replacing \(oldHost)…")
            try unlink(old, deleteTunnel: true, log: log)
        }

        let tunnelName = TunnelConfig.tunnelName(for: hostname)
        let configPath = TunnelConfig.path(for: hostname)

        log("Tunnel \(tunnelName)…")
        let tunnel = try Cloudflared.create(name: tunnelName)
        log("DNS \(hostname) → \(tunnelName)…")
        try Cloudflared.routeDNS(tunnel: tunnelName, hostname: hostname)

        let yaml = TunnelConfig.render(tunnelID: tunnel.id, hostname: hostname, origin: request.origin)
        if (try? String(contentsOfFile: configPath, encoding: .utf8)) != yaml {
            log("Writing \(configPath)")
            try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)
        }
        let config = try TunnelConfig.parse(path: configPath)

        try Settings.update {
            $0.projects[hostname] = Settings.Project(directory: request.directory, name: name, domain: domain)
        }

        let agent = LaunchAgent(hostname: hostname)
        try agent.install(configPath: config.path, tunnelName: config.tunnelID)
        if start {
            log("Starting \(agent.label)")
            if agent.isLoaded { agent.stop() }
            try agent.start()
        }
        return config
    }

    /// Moves a tunnel to a new name and/or domain, keeping its origin and folder.
    @discardableResult
    public static func rename(_ row: SiteRow, name: String?, domain: String?, log: (String) -> Void = { _ in }) throws -> TunnelConfig {
        guard let config = row.config else { throw CloudError("\(row.domain) has no config to rename") }
        let request = LinkRequest(
            name: name ?? row.name,
            domain: domain ?? row.project?.domain ?? String(config.hostname.drop { $0 != "." }.dropFirst()),
            origin: config.originSpec,
            directory: row.directory
        )
        let newHost = "\(Folder.slug(request.name)).\(request.domain ?? "")"
        guard newHost != config.hostname else { return config }
        let wasRunning = row.state.isRunning
        // link() replaces the old tunnel itself when it knows the folder; otherwise remove it here.
        if row.directory == nil { try unlink(row, deleteTunnel: true, log: log) }
        return try link(request, start: wasRunning, log: log)
    }

    /// Turns a tunnel on. A tunnel without a LaunchAgent gets one; one already running by hand is left alone.
    public static func start(_ row: SiteRow) throws {
        guard let config = row.config, let agent = row.agent else { throw CloudError("\(row.name) isn't linked; run `tunnel link`") }
        if case .running(let pid, false) = row.state {
            throw CloudError("\(config.hostname) is already running by hand (pid \(pid)); `tunnel adopt` hands it to launchd")
        }
        if !agent.isInstalled { try agent.install(configPath: config.path, tunnelName: config.tunnelID) }
        try agent.start()
    }

    /// Turns a tunnel off, including a cloudflared started outside launchd.
    public static func stop(_ row: SiteRow) throws {
        guard let config = row.config, let agent = row.agent else { throw CloudError("\(row.name) isn't linked") }
        agent.stop()
        killManual(config)
    }

    public static func restart(_ row: SiteRow) throws {
        try stop(row)
        guard let config = row.config else { return }
        let agent = LaunchAgent(hostname: config.hostname)
        if !agent.isInstalled { try agent.install(configPath: config.path, tunnelName: config.tunnelID) }
        try agent.start()
    }

    /// Replaces a hand-started cloudflared with a LaunchAgent for the same config.
    public static func adopt(_ row: SiteRow) throws {
        guard let config = row.config, let agent = row.agent else { throw CloudError("\(row.name) has no config file to adopt") }
        try agent.install(configPath: config.path, tunnelName: config.tunnelID)
        killManual(config)
        try agent.start()
    }

    /// Removes the LaunchAgent and config. With `deleteTunnel`, also deletes the tunnel, its DNS record and credentials.
    public static func unlink(_ row: SiteRow, deleteTunnel: Bool, log: (String) -> Void = { _ in }) throws {
        if let config = row.config {
            LaunchAgent(hostname: config.hostname).uninstall()
            killManual(config)
            try? FileManager.default.removeItem(atPath: config.path)
            try? Settings.update { $0.projects[config.hostname] = nil }
            log("Removed \(config.path) and its LaunchAgent")
        }
        guard deleteTunnel else { return }
        guard let id = row.tunnel?.id ?? row.config?.tunnelID else { return }
        removeDNS(forTunnelIDs: [id], log: log)
        try Cloudflared.delete(tunnel: id)
        try? FileManager.default.removeItem(atPath: "\(Paths.cloudflared)/\(id).json")
        log("Deleted tunnel \(row.tunnel?.name ?? id)")
    }

    /// What `clean` will remove, so callers can show it before confirming.
    public struct CleanPlan: Sendable {
        public let agents: [String]
        public let configs: [String]
        public let tunnels: [TunnelInfo]
        public let hostnames: [String]
        public let legacyState: String?

        public var isEmpty: Bool { agents.isEmpty && configs.isEmpty && tunnels.isEmpty && legacyState == nil }
    }

    static let legacyStateDir = "\(Paths.home)/.tunnel"

    public static func cleanPlan() throws -> CleanPlan {
        let fm = FileManager.default
        let agents = ((try? fm.contentsOfDirectory(atPath: Paths.launchAgents)) ?? [])
            .filter { $0.hasPrefix(LaunchAgent.labelPrefix) && $0.hasSuffix(".plist") }
            .map { "\(Paths.launchAgents)/\($0)" }
        let (configs, _) = TunnelConfig.loadAll()
        let configFiles = ((try? fm.contentsOfDirectory(atPath: Paths.cloudflared)) ?? [])
            .filter { $0.hasPrefix("config-") && ($0.hasSuffix(".yml") || $0.hasSuffix(".yaml")) }
            .map { "\(Paths.cloudflared)/\($0)" }
        return CleanPlan(
            agents: agents.sorted(),
            configs: configFiles.sorted(),
            tunnels: try Cloudflared.list(),
            hostnames: configs.map(\.hostname),
            legacyState: fm.fileExists(atPath: legacyStateDir) ? legacyStateDir : nil
        )
    }

    /// Fresh start: stops every tunnel and deletes every LaunchAgent, config, tunnel, tunnel DNS record and
    /// credentials file. Keeps cert.pem, so you stay logged in to Cloudflare, and the default domain.
    public static func clean(_ plan: CleanPlan, log: (String) -> Void = { _ in }) throws {
        let fm = FileManager.default
        for plist in plan.agents {
            let label = ((plist as NSString).lastPathComponent as NSString).deletingPathExtension
            Shell.run("launchctl", ["bootout", "gui/\(getuid())/\(label)"])
            try? fm.removeItem(atPath: plist)
            log("Removed LaunchAgent \(label)")
        }

        // Anything still running a tunnel was started by hand (or by the old ~/bin/tunnel script).
        let stray = Shell.run("pgrep", ["-f", "cloudflared.* tunnel .*run"]).stdout.split(separator: "\n").compactMap { Int32($0) }
        for pid in stray { kill(pid, SIGTERM) }
        if !stray.isEmpty { log("Stopped \(stray.count) cloudflared process(es)") }

        removeDNS(forTunnelIDs: Set(plan.tunnels.map(\.id)), log: log)

        var failures: [String] = []
        var kept = Set<String>()
        for tunnel in plan.tunnels {
            do {
                try Cloudflared.delete(tunnel: tunnel.id)
                log("Deleted tunnel \(tunnel.name)")
            } catch {
                failures.append("\(tunnel.name): \(error.localizedDescription)")
                kept.insert(tunnel.id)
            }
        }

        for path in plan.configs {
            try? fm.removeItem(atPath: path)
            log("Removed \(path)")
        }
        // Credentials files are named <tunnel-uuid>.json; cert.pem (the login) stays, and so do the
        // credentials of any tunnel that failed to delete.
        for file in (try? fm.contentsOfDirectory(atPath: Paths.cloudflared)) ?? []
        where file.hasSuffix(".json") && !kept.contains((file as NSString).deletingPathExtension) {
            try? fm.removeItem(atPath: "\(Paths.cloudflared)/\(file)")
        }
        try? Settings.update { $0.projects = [:] }
        if let legacy = plan.legacyState {
            try? fm.removeItem(atPath: legacy)
            log("Removed \(legacy) (old tunnel script state)")
        }

        if !failures.isEmpty { throw CloudError("Some tunnels couldn't be deleted:\n" + failures.joined(separator: "\n")) }
    }

    static func removeDNS(forTunnelIDs ids: Set<String>, log: (String) -> Void) {
        do {
            let removed = try CloudflareDNS.fromCert().deleteRecords(forTunnelIDs: ids)
            removed.forEach { log("Deleted DNS record \($0)") }
        } catch {
            log("Couldn't delete DNS records (\(error.localizedDescription)); remove them in the Cloudflare dashboard")
        }
    }

    static func killManual(_ config: TunnelConfig) {
        for pid in Cloudflared.pids(forConfig: config.path) { kill(pid, SIGTERM) }
    }
}
