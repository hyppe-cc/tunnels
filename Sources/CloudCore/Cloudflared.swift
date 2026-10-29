import Foundation

public struct TunnelInfo: Hashable, Sendable, Decodable {
    public struct Connection: Hashable, Sendable, Decodable {
        public let colo_name: String
    }
    public let id: String
    public let name: String
    public let connections: [Connection]

    public init(id: String, name: String, connections: [Connection]) {
        self.id = id
        self.name = name
        self.connections = connections
    }

    // cloudflared prints `null` rather than `[]` for no connections.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        connections = try c.decodeIfPresent([Connection].self, forKey: .connections) ?? []
    }

    enum CodingKeys: String, CodingKey { case id, name, connections }

    public var isConnected: Bool { !connections.isEmpty }
}

public enum Cloudflared {
    public static var isInstalled: Bool { Shell.which("cloudflared") != nil }

    public static func list() throws -> [TunnelInfo] {
        let result = try Shell.check("cloudflared", ["tunnel", "list", "--output", "json"])
        // With no tunnels the output is `null`, not `[]`.
        do {
            return try JSONDecoder().decode([TunnelInfo]?.self, from: Data(result.stdout.utf8)) ?? []
        } catch {
            throw CloudError("Unexpected output from `cloudflared tunnel list`: \(result.stdout.prefix(200))")
        }
    }

    /// Creates the tunnel, or returns the existing one with that name.
    public static func create(name: String) throws -> TunnelInfo {
        if let existing = try list().first(where: { $0.name == name }) { return existing }
        try Shell.check("cloudflared", ["tunnel", "create", name])
        guard let created = try list().first(where: { $0.name == name }) else {
            throw CloudError("cloudflared created \(name) but it isn't in `tunnel list`")
        }
        return created
    }

    /// Points the hostname's CNAME at the tunnel. `--overwrite-dns` makes re-linking idempotent.
    public static func routeDNS(tunnel: String, hostname: String) throws {
        try Shell.check("cloudflared", ["tunnel", "route", "dns", "--overwrite-dns", tunnel, hostname])
    }

    public static func delete(tunnel: String) throws {
        // Clears stale connections first, otherwise delete refuses.
        Shell.run("cloudflared", ["tunnel", "cleanup", tunnel])
        try Shell.check("cloudflared", ["tunnel", "delete", tunnel])
    }

    /// PIDs of cloudflared processes running a given config file, whoever started them.
    public static func pids(forConfig path: String) -> [Int32] {
        let result = Shell.run("pgrep", ["-f", "cloudflared.*\(NSRegularExpression.escapedPattern(for: path))"])
        return result.stdout.split(separator: "\n").compactMap { Int32($0) }
    }
}
