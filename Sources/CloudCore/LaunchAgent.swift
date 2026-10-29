import Foundation

/// One LaunchAgent per tunnel, so tunnels outlive the app and come back after a reboot.
public struct LaunchAgent: Sendable {
    public let hostname: String

    public init(hostname: String) { self.hostname = hostname }

    public static let labelPrefix = "cc.hyppe.tunnels."
    public var label: String { Self.labelPrefix + hostname }
    public var plistPath: String { "\(Paths.launchAgents)/\(label).plist" }
    public var logPath: String { "\(Paths.logs)/\(hostname).log" }
    var domain: String { "gui/\(getuid())" }
    var service: String { "\(domain)/\(label)" }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    /// The PID launchd reports for the agent, nil when it isn't loaded or isn't running.
    public func runningPID() -> Int32? {
        let result = Shell.run("launchctl", ["print", service])
        guard result.ok else { return nil }
        for line in result.stdout.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("pid = "), let pid = Int32(trimmed.dropFirst(6)) { return pid }
        }
        return nil
    }

    public var isLoaded: Bool { Shell.run("launchctl", ["print", service]).ok }

    public func install(configPath: String, tunnelName: String) throws {
        guard let cloudflared = Shell.which("cloudflared") else { throw CloudError("cloudflared is not installed") }
        let fm = FileManager.default
        try fm.createDirectory(atPath: Paths.launchAgents, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: Paths.logs, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [cloudflared, "tunnel", "--config", configPath, "run", tunnelName],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath))
    }

    public func start() throws {
        guard isInstalled else { throw CloudError("\(hostname) has no LaunchAgent; run `tunnel adopt` or `tunnel link`") }
        if isLoaded {
            try Shell.check("launchctl", ["kickstart", service])
        } else {
            try Shell.check("launchctl", ["bootstrap", domain, plistPath])
        }
    }

    /// Unloads the agent; KeepAlive would restart it if it were only killed.
    public func stop() {
        Shell.run("launchctl", ["bootout", service])
    }

    public func uninstall() {
        stop()
        try? FileManager.default.removeItem(atPath: plistPath)
    }
}
