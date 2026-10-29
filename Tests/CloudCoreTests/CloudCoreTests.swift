import Foundation
import Testing
@testable import CloudCore

struct TunnelConfigTests {
    func fixture(_ name: String) -> String {
        Bundle.module.path(forResource: "Fixtures/config-\(name)", ofType: "yml")!
    }

    @Test func hostOrigin() throws {
        let config = try TunnelConfig.parse(path: fixture("blog.example.com"))
        #expect(config.hostname == "blog.example.com")
        #expect(config.tunnelID == "11111111-1111-4111-8111-111111111111")
        #expect(config.origin == .host("blog.test"))
        #expect(config.originSpec == OriginSpec(service: "https://blog.test", hostHeader: "blog.test"))
    }

    @Test func portOrigin() throws {
        let config = try TunnelConfig.parse(path: fixture("api.example.com"))
        #expect(config.origin == .port(8787))
    }

    @Test func loopbackWithHostHeaderIsHost() throws {
        let config = try TunnelConfig.parse(path: fixture("shop.example.com"))
        #expect(config.origin == .host("shop.test"))
    }

    @Test func tunnelName() {
        #expect(TunnelConfig.tunnelName(for: "api.example.com") == "tunnel-api-example-com")
    }

    @Test func parseOriginSpec() throws {
        #expect(try OriginSpec.parse("8787") == .port(8787))
        #expect(try OriginSpec.parse(":3000") == .port(3000))
        #expect(try OriginSpec.parse("myapp.test") == OriginSpec(service: "https://myapp.test", hostHeader: "myapp.test"))
        #expect(try OriginSpec.parse("http://localhost:5173") == OriginSpec(service: "http://localhost:5173", hostHeader: nil))
    }

    @Test func renderRoundTrips() throws {
        let yaml = TunnelConfig.render(tunnelID: "abc", hostname: "api.example.com", origin: try .parse("myapp.test"), dir: "/x")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("config-api.yml").path
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        let config = try TunnelConfig.parse(path: path)
        #expect(config.hostname == "api.example.com")
        #expect(config.service == "https://myapp.test")
        #expect(config.origin == .host("myapp.test"))
        #expect(yaml.contains("originServerName: myapp.test"))
        #expect(yaml.contains("noTLSVerify: true"))
    }

    @Test func renderPort() throws {
        let yaml = TunnelConfig.render(tunnelID: "abc", hostname: "api.example.com", origin: .port(8787))
        #expect(yaml.contains("service: http://127.0.0.1:8787"))
        #expect(!yaml.contains("originRequest"))
    }
}

struct SettingsTests {
    @Test func roundTripsAndFindsProjectByFolder() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("tunnel-settings-\(UUID()).json").path
        try Settings.update(path: path) {
            $0.defaultDomain = "example.com"
            $0.projects["api.example.com"] = .init(directory: "/tmp/myapp", name: "api", domain: "example.com")
        }
        let settings = Settings.load(path: path)
        #expect(settings.defaultDomain == "example.com")
        #expect(settings.project(containing: "/tmp/myapp/app/Http")?.hostname == "api.example.com")
        #expect(settings.project(containing: "/tmp/myapp-other") == nil)
    }

    @Test func missingDomainIsAnError() {
        #expect(throws: CloudError.self) { try Settings().requireDomain() }
    }

    @Test func slug() {
        #expect(Folder.slug("My App") == "my-app")
        #expect(Folder.slug("my-shop") == "my-shop")
    }
}

struct CloudflaredTests {
    @Test func decodesNullList() throws {
        #expect(try JSONDecoder().decode([TunnelInfo]?.self, from: Data("null".utf8)) == nil)
        let tunnels = try JSONDecoder().decode([TunnelInfo].self, from: Data(#"[{"id":"a","name":"n","connections":null}]"#.utf8))
        #expect(tunnels.first?.connections.isEmpty == true)
    }
}

struct InventoryTests {
    @Test func joinsConfigsTunnelsAndProjects() throws {
        let dir = Bundle.module.resourcePath! + "/Fixtures"
        let configs = TunnelConfig.loadAll(dir: dir).configs
        let tunnels = [
            TunnelInfo(id: "11111111-1111-4111-8111-111111111111", name: "tunnel-blog-example-com", connections: []),
            TunnelInfo(id: "22222222-2222-4222-8222-222222222222", name: "tunnel-api-example-com", connections: [.init(colo_name: "qro01")]),
            TunnelInfo(id: "55555555-5555-4555-8555-555555555555", name: "old-tunnel", connections: []),
        ]
        var settings = Settings()
        settings.projects["api.example.com"] = .init(directory: "/h/myapp", name: "api", domain: "example.com")
        let inventory = Inventory.build(configs: configs, tunnels: tunnels, settings: settings, probe: false)

        #expect(inventory.find("blog")?.config?.hostname == "blog.example.com")
        #expect(inventory.find("blog")?.state == .stopped)
        #expect(inventory.find("api")?.directory == "/h/myapp")
        #expect(inventory.row(forDirectory: "/h/myapp", settings: settings)?.domain == "api.example.com")
        #expect(inventory.find("old-tunnel")?.state == .broken("no config file"))
        // docs' tunnel isn't in the list above, so its config points at a deleted tunnel.
        if case .broken = inventory.find("docs.example.com")?.state {} else { Issue.record("docs should be broken") }
    }
}
