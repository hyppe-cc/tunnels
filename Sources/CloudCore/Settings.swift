import Foundation

/// ~/.config/tunnel/settings.json: the default domain, plus what each tunnel was linked from.
public struct Settings: Codable, Sendable {
    /// Domain new tunnels go on: `<name>.<defaultDomain>`.
    public var defaultDomain: String?
    /// Local TLD used to guess a folder's origin (`myapp` → `myapp.test`). Defaults to `test`.
    public var localTLD: String?
    /// Keyed by public hostname.
    public var projects: [String: Project] = [:]

    public struct Project: Codable, Hashable, Sendable {
        /// Folder the tunnel was linked from, so `tunnel start` etc. work from inside it.
        public var directory: String?
        /// The subdomain, which may differ from the folder name (backend → api).
        public var name: String
        public var domain: String

        public init(directory: String?, name: String, domain: String) {
            self.directory = directory
            self.name = name
            self.domain = domain
        }
    }

    public init() {}

    public var tld: String { localTLD ?? "test" }

    public static func load(path: String = Paths.settings) -> Settings {
        guard let data = FileManager.default.contents(atPath: path),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(path: String = Paths.settings) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    /// Applies a change to the settings on disk.
    public static func update(path: String = Paths.settings, _ change: (inout Settings) -> Void) throws {
        var settings = load(path: path)
        change(&settings)
        try settings.save(path: path)
    }

    public func requireDomain() throws -> String {
        guard let domain = defaultDomain, !domain.isEmpty else {
            throw CloudError("No default domain; set one with `tunnel domain example.com` (or pass --domain)")
        }
        return domain
    }

    /// The project linked from `directory` or a folder above it (deepest match wins).
    public func project(containing directory: String) -> (hostname: String, project: Project)? {
        let dir = (directory as NSString).resolvingSymlinksInPath
        return projects
            .compactMap { host, project -> (String, Project, Int)? in
                guard let root = project.directory, dir == root || dir.hasPrefix(root + "/") else { return nil }
                return (host, project, root.count)
            }
            .max { $0.2 < $1.2 }
            .map { ($0.0, $0.1) }
    }
}

public enum Folder {
    /// APP_NAME from a folder's .env, when it's set to something other than Laravel's default.
    public static func title(in directory: String) -> String? {
        guard let env = try? String(contentsOfFile: "\(directory)/.env", encoding: .utf8) else { return nil }
        for line in env.split(separator: "\n") where line.hasPrefix("APP_NAME=") {
            let value = line.dropFirst("APP_NAME=".count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty || value == "Laravel" ? nil : value
        }
        return nil
    }

    /// A DNS-safe subdomain from a folder name: `My App` → `my-app`.
    public static func slug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = name.lowercased()
            .map { String($0).unicodeScalars.allSatisfy(allowed.contains) ? String($0) : "-" }
            .joined()
        return slug.split(separator: "-").joined(separator: "-")
    }
}
