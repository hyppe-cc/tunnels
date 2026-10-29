import Foundation
import Yams

public enum Origin: Hashable, Sendable {
    /// A local hostname, e.g. `myapp.test`, sent as the Host header.
    case host(String)
    /// A local port, e.g. `php artisan serve` on 8787.
    case port(Int)
    case other(String)

    public var label: String {
        switch self {
        case .host(let host): host
        case .port(let port): ":\(port)"
        case .other(let service): service
        }
    }

    static func parse(service: String, hostHeader: String?) -> Origin {
        guard let url = URL(string: service), let host = url.host else { return .other(service) }
        if OriginSpec.isLoopback(host) {
            // Loopback that rewrites Host is still a named site behind a local web server.
            if let hostHeader, hostHeader.contains(".") { return .host(hostHeader) }
            return .port(url.port ?? (url.scheme == "https" ? 443 : 80))
        }
        return .host(host)
    }
}

/// Where a tunnel sends traffic: the `service` URL and the Host header to send with it.
public struct OriginSpec: Hashable, Sendable {
    public let service: String
    public let hostHeader: String?

    public init(service: String, hostHeader: String?) {
        self.service = service
        self.hostHeader = hostHeader
    }

    public static func port(_ port: Int) -> OriginSpec {
        OriginSpec(service: "http://127.0.0.1:\(port)", hostHeader: nil)
    }

    /// `8787`, `:8787`, `myapp.test`, `https://myapp.test` or `http://127.0.0.1:3000`.
    public static func parse(_ text: String) throws -> OriginSpec {
        let text = text.trimmingCharacters(in: .whitespaces)
        if let port = Int(text.hasPrefix(":") ? String(text.dropFirst()) : text) { return .port(port) }
        let withScheme = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: withScheme), let host = url.host else { throw CloudError("Not a URL or port: \(text)") }
        // Name-based origins get their name as the Host header, which is what local web servers route on.
        return OriginSpec(service: withScheme, hostHeader: isLoopback(host) ? nil : host)
    }

    static func isLoopback(_ host: String) -> Bool { host == "127.0.0.1" || host == "localhost" || host == "::1" }
}

public struct TunnelConfig: Hashable, Sendable {
    public let path: String
    public let tunnelID: String
    public let hostname: String
    public let service: String
    public let hostHeader: String?
    public let origin: Origin

    public var originSpec: OriginSpec { OriginSpec(service: service, hostHeader: hostHeader) }

    public var publicURL: String { "https://\(hostname)" }
    /// `tunnel-api-example-com`: one Cloudflare tunnel per hostname.
    public static func tunnelName(for hostname: String) -> String {
        "tunnel-" + hostname.replacingOccurrences(of: ".", with: "-")
    }

    public static func path(for hostname: String, dir: String = Paths.cloudflared) -> String {
        "\(dir)/config-\(hostname).yml"
    }

    public static func parse(path: String) throws -> TunnelConfig {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw CloudError("\(path): not a YAML mapping")
        }
        guard let tunnel = root["tunnel"] as? String else { throw CloudError("\(path): missing `tunnel`") }
        let ingress = root["ingress"] as? [[String: Any]] ?? []
        guard let rule = ingress.first(where: { $0["hostname"] != nil }),
              let hostname = rule["hostname"] as? String,
              let service = rule["service"] as? String
        else { throw CloudError("\(path): no ingress rule with a hostname") }
        let hostHeader = (rule["originRequest"] as? [String: Any])?["httpHostHeader"] as? String
        return TunnelConfig(
            path: path, tunnelID: tunnel, hostname: hostname, service: service, hostHeader: hostHeader,
            origin: .parse(service: service, hostHeader: hostHeader)
        )
    }

    public static func loadAll(dir: String = Paths.cloudflared) -> (configs: [TunnelConfig], errors: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var configs: [TunnelConfig] = [], errors: [String] = []
        for file in files.sorted() where file.hasPrefix("config-") && (file.hasSuffix(".yml") || file.hasSuffix(".yaml")) {
            do { configs.append(try parse(path: "\(dir)/\(file)")) } catch { errors.append("\(error.localizedDescription)") }
        }
        return (configs, errors)
    }

    /// YAML for a new tunnel, in the same shape as the hand-written configs.
    public static func render(tunnelID: String, hostname: String, origin: OriginSpec, dir: String = Paths.cloudflared) -> String {
        var lines = [
            "tunnel: \(tunnelID)",
            "credentials-file: \(dir)/\(tunnelID).json",
            "",
            "ingress:",
            "  - hostname: \(hostname)",
            "    service: \(origin.service)",
        ]
        var request: [String] = []
        if let host = origin.hostHeader { request.append("httpHostHeader: \(host)") }
        if origin.service.hasPrefix("https://") {
            // Local certificates are self-signed, so verify against the local name but don't require a trusted chain.
            if let host = origin.hostHeader { request.append("originServerName: \(host)") }
            request.append("noTLSVerify: true")
        }
        if !request.isEmpty {
            lines.append("    originRequest:")
            lines += request.map { "      \($0)" }
        }
        lines.append("  - service: http_status:404")
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct CloudError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
