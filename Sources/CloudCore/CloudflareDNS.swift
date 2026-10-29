import Foundation

/// Deletes the CNAMEs that point at tunnels. cloudflared can create these (`tunnel route dns`) but not remove them,
/// so this uses the zone token that `cloudflared tunnel login` stores in cert.pem — the same one route dns uses.
public struct CloudflareDNS: Sendable {
    let zoneID: String
    let apiToken: String

    struct Token: Decodable {
        let zoneID: String
        let apiToken: String
    }

    public static func fromCert(path: String = "\(Paths.cloudflared)/cert.pem") throws -> CloudflareDNS {
        let pem = try String(contentsOfFile: path, encoding: .utf8)
        guard let start = pem.range(of: "-----BEGIN ARGO TUNNEL TOKEN-----"),
              let end = pem.range(of: "-----END ARGO TUNNEL TOKEN-----", range: start.upperBound..<pem.endIndex)
        else { throw CloudError("\(path) has no tunnel token; run `cloudflared tunnel login`") }
        let base64 = pem[start.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(base64)) else { throw CloudError("Couldn't decode the token in \(path)") }
        let token = try JSONDecoder().decode(Token.self, from: data)
        return CloudflareDNS(zoneID: token.zoneID, apiToken: token.apiToken)
    }

    struct Record: Decodable {
        let id: String
        let name: String
        let content: String
    }

    struct Response<T: Decodable>: Decodable {
        let success: Bool
        let result: T?
        let errors: [APIError]
    }

    struct APIError: Decodable { let message: String }

    /// Deletes every CNAME whose target is one of these tunnels. Returns the hostnames removed.
    public func deleteRecords(forTunnelIDs ids: Set<String>) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let targets = Set(ids.map { "\($0).cfargotunnel.com" })
        let records: [Record] = try request("GET", "dns_records?type=CNAME&per_page=5000")
        var deleted: [String] = []
        for record in records where targets.contains(record.content) {
            let _: Deleted = try request("DELETE", "dns_records/\(record.id)")
            deleted.append(record.name)
        }
        return deleted
    }

    struct Deleted: Decodable { let id: String }

    func request<T: Decodable>(_ method: String, _ path: String) throws -> T {
        var request = URLRequest(url: URL(string: "https://api.cloudflare.com/client/v4/zones/\(zoneID)/\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            box.data = data
            box.error = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = box.error { throw error }
        guard let response = try? JSONDecoder().decode(Response<T>.self, from: box.data ?? Data()) else {
            throw CloudError("Unexpected Cloudflare API response to \(method) \(path)")
        }
        guard response.success, let result = response.result else {
            throw CloudError("Cloudflare API: " + response.errors.map(\.message).joined(separator: "; "))
        }
        return result
    }

    final class ResultBox: @unchecked Sendable {
        var data: Data?
        var error: Error?
    }
}
