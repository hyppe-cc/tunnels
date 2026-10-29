import ArgumentParser
import CloudCore
import Foundation

struct Cloud: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tunnel",
        abstract: "Share local projects on your own domain through Cloudflare tunnels.",
        subcommands: [Status.self, Link.self, Rename.self, Domain.self, Start.self, Stop.self, Restart.self, Adopt.self,
                      Unlink.self, Clean.self, Logs.self, Open.self],
        defaultSubcommand: Status.self
    )
}

/// A name, hostname or tunnel name; defaults to the tunnel linked from the current folder.
struct Target: ParsableArguments {
    @Argument(help: "Name, hostname or tunnel name (defaults to the tunnel linked from this folder).")
    var target: String?

    func resolve(_ inventory: Inventory) throws -> SiteRow {
        if let target {
            guard let row = inventory.find(target) else { throw ValidationError("No tunnel named \(target)") }
            return row
        }
        let cwd = FileManager.default.currentDirectoryPath
        guard let row = inventory.row(forDirectory: cwd) else {
            throw ValidationError("No tunnel is linked from \(cwd); run `tunnel link` here or pass a name")
        }
        return row
    }
}

func say(_ message: String) { print(message) }

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show your tunnels and whether each one is up.")

    @Argument(help: "Show only this tunnel.") var target: String?

    func run() throws {
        let inventory = Inventory.load()
        inventory.warnings.forEach { FileHandle.standardError.write(Data("warning: \($0)\n".utf8)) }

        let rows: [SiteRow]
        if let target {
            guard let row = inventory.find(target) else { throw ValidationError("No tunnel named \(target)") }
            rows = [row]
        } else if let here = inventory.row(forDirectory: FileManager.default.currentDirectoryPath) {
            rows = [here]
        } else {
            rows = inventory.rows
        }

        if rows.isEmpty {
            let domain = Settings.load().defaultDomain
            say("No tunnels yet. Run `tunnel link` inside a project folder"
                + (domain.map { " to share it on <folder>.\($0)." } ?? ", after `tunnel domain example.com`."))
            return
        }
        let table = [["DOMAIN", "TITLE", "ORIGIN", "STATE", "EDGE"]] + rows.map { row in
            [
                row.domain,
                row.title == row.name ? "" : row.title,
                row.originLabel,
                row.state.label + (row.state == .stopped && !row.hasAgent ? " (no agent)" : ""),
                row.tunnel.map { $0.connections.isEmpty ? "" : "\($0.connections.count) conn" } ?? "",
            ]
        }
        printTable(table)
    }

    func printTable(_ table: [[String]]) {
        let widths = (0..<table[0].count).map { col in table.map { $0[col].count }.max() ?? 0 }
        for line in table {
            print(zip(line, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ")
                .trimmingCharacters(in: .whitespaces))
        }
    }
}

struct Link: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Share the current folder as <name>.<domain> and start it.",
        discussion: """
            Run inside a project folder. The name defaults to the folder name and the domain to `tunnel domain`.
            The origin defaults to https://<folder>.test (or http), whichever answers.

              tunnel link                         # ~/code/myapp → myapp.example.com
              tunnel link --name api              # ~/code/backend → api.example.com
              tunnel link --domain other.dev      # → myapp.other.dev
              tunnel link --port 8787             # → http://127.0.0.1:8787
              tunnel link --origin myapp.test

            Linking a folder again with a different name or domain replaces its old tunnel.
            """
    )

    @Option(name: .shortAndLong, help: "Subdomain to publish as (default: the folder name).") var name: String?
    @Option(name: .shortAndLong, help: "Domain to publish on (default: the one set with `tunnel domain`).") var domain: String?
    @Option(help: "Local URL or host to send traffic to, e.g. myapp.test or http://localhost:3000.") var origin: String?
    @Option(help: "Send traffic to http://127.0.0.1:<port>.") var port: Int?
    @Flag(help: "Set it up without starting it.") var noStart = false

    func run() throws {
        let cwd = FileManager.default.currentDirectoryPath
        let folder = (cwd as NSString).lastPathComponent
        let settings = Settings.load()
        let previous = settings.project(containing: cwd).flatMap { $0.project.directory == cwd ? $0 : nil }

        let spec: OriginSpec
        if let port {
            spec = .port(port)
        } else if let origin {
            spec = try .parse(origin)
        } else if let previous, let config = try? TunnelConfig.parse(path: TunnelConfig.path(for: previous.hostname)) {
            spec = config.originSpec
        } else if let guessed = Operations.guessOrigin(forFolder: folder, settings: settings) {
            spec = guessed
        } else {
            throw ValidationError("Nothing answers at \(Folder.slug(folder)).\(settings.tld); pass --origin or --port")
        }

        let request = Operations.LinkRequest(
            name: name ?? previous?.project.name ?? folder,
            domain: domain ?? previous?.project.domain,
            origin: spec,
            directory: cwd
        )
        let config = try Operations.link(request, start: !noStart, log: say)
        say("\n\(config.publicURL) → \(config.origin.label)")
    }
}

struct Rename: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Move a tunnel to a new name and/or domain (replaces its tunnel and DNS record)."
    )
    @OptionGroup var target: Target
    @Option(name: .shortAndLong, help: "New subdomain.") var name: String?
    @Option(name: .shortAndLong, help: "New domain.") var domain: String?

    func run() throws {
        guard name != nil || domain != nil else { throw ValidationError("Pass --name and/or --domain") }
        let row = try target.resolve(Inventory.load())
        let config = try Operations.rename(row, name: name, domain: domain, log: say)
        say("\n\(config.publicURL) → \(config.origin.label)")
    }
}

struct Domain: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show or set the default domain for new tunnels.")
    @Argument(help: "e.g. example.com") var domain: String?

    func run() throws {
        guard let domain else {
            return say(Settings.load().defaultDomain ?? "No default domain; set one with `tunnel domain example.com`")
        }
        let clean = domain.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        try Settings.update { $0.defaultDomain = clean }
        say("New tunnels go on <name>.\(clean)")
    }
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Turn a tunnel on (via launchd).")
    @OptionGroup var target: Target
    func run() throws {
        let row = try target.resolve(Inventory.load())
        try Operations.start(row)
        say("Started \(row.publicURL ?? row.name)")
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Turn a tunnel off.")
    @OptionGroup var target: Target
    func run() throws {
        let row = try target.resolve(Inventory.load())
        try Operations.stop(row)
        say("Stopped \(row.publicURL ?? row.name)")
    }
}

struct Restart: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Restart a tunnel.")
    @OptionGroup var target: Target
    func run() throws {
        let row = try target.resolve(Inventory.load())
        try Operations.restart(row)
        say("Restarted \(row.publicURL ?? row.name)")
    }
}

struct Adopt: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Hand a tunnel you started by hand over to launchd.")
    @OptionGroup var target: Target
    func run() throws {
        let row = try target.resolve(Inventory.load())
        try Operations.adopt(row)
        say("\(row.publicURL ?? row.name) now runs as \(row.agent?.label ?? "a LaunchAgent")")
    }
}

struct Unlink: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove a tunnel's config and LaunchAgent.")
    @OptionGroup var target: Target
    @Flag(help: "Also delete the tunnel in Cloudflare, its DNS record and its credentials file.") var deleteTunnel = false
    func run() throws {
        let row = try target.resolve(Inventory.load())
        try Operations.unlink(row, deleteTunnel: deleteTunnel, log: say)
    }
}

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove every tunnel, DNS record, config and LaunchAgent for a fresh start.",
        discussion: "Keeps ~/.cloudflared/cert.pem, so you stay logged in to Cloudflare."
    )
    @Flag(name: .shortAndLong, help: "Don't ask for confirmation.") var yes = false

    func run() throws {
        let plan = try Operations.cleanPlan()
        if plan.isEmpty { return say("Nothing to clean.") }

        say("This removes:")
        plan.tunnels.forEach { say("  tunnel      \($0.name)\($0.isConnected ? "  (live)" : "")") }
        plan.hostnames.forEach { say("  DNS         \($0)") }
        plan.configs.forEach { say("  config      \($0)") }
        plan.agents.forEach { say("  LaunchAgent \($0)") }
        plan.legacyState.map { say("  old state   \($0)") }
        say("Every shared URL stops working. cert.pem (your Cloudflare login) is kept.")

        if !yes {
            print("\nType \"clean\" to continue: ", terminator: "")
            guard readLine()?.trimmingCharacters(in: .whitespaces) == "clean" else { return say("Cancelled.") }
        }
        try Operations.clean(plan, log: say)
        say("\nClean. `tunnel link` in a project folder starts fresh.")
    }
}

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show a tunnel's log.")
    @OptionGroup var target: Target
    @Flag(name: .shortAndLong, help: "Follow the log.") var follow = false
    func run() throws {
        let row = try target.resolve(Inventory.load())
        guard let agent = row.agent else { throw ValidationError("\(row.name) isn't linked") }
        guard FileManager.default.fileExists(atPath: agent.logPath) else {
            throw ValidationError("No log yet at \(agent.logPath)")
        }
        let tail = Process()
        tail.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        tail.arguments = (follow ? ["-f"] : ["-n", "50"]) + [agent.logPath]
        try tail.run()
        tail.waitUntilExit()
    }
}

struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open the public URL in the browser.")
    @OptionGroup var target: Target
    func run() throws {
        let row = try target.resolve(Inventory.load())
        guard let url = row.publicURL else { throw ValidationError("\(row.name) isn't linked") }
        Shell.run("open", [url])
    }
}

Cloud.main()
