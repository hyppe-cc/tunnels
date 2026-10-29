import CloudCore
import Foundation
import Observation

@MainActor
@Observable
final class Store {
    var inventory: Inventory?
    var busy: Set<String> = []
    var error: String?
    private var timer: Timer?

    var hasTunnels: Bool { inventory?.rows.contains { $0.config != nil || $0.tunnel != nil } ?? false }
    var anyRunning: Bool { inventory?.rows.contains { $0.state.isRunning } ?? false }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            let inventory = await Task.detached { Inventory.load() }.value
            self.inventory = inventory
            self.defaultDomain = Settings.load().defaultDomain
        }
    }

    /// Runs a Core operation off the main thread, marking the row busy until the inventory reloads.
    func perform(_ row: SiteRow, _ action: @escaping @Sendable (SiteRow) throws -> Void) {
        busy.insert(row.id)
        Task {
            let failure = await Task.detached { () -> String? in
                do { try action(row); return nil } catch { return error.localizedDescription }
            }.value
            self.error = failure
            self.inventory = await Task.detached { Inventory.load() }.value
            self.busy.remove(row.id)
        }
    }

    func toggle(_ row: SiteRow) {
        perform(row) { row in
            if row.state.isRunning { try Operations.stop(row) } else { try Operations.start(row) }
        }
    }

    var defaultDomain: String? = Settings.load().defaultDomain

    func setDefaultDomain(_ domain: String) {
        let clean = domain.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
        do {
            try Settings.update { $0.defaultDomain = clean.isEmpty ? nil : clean }
            defaultDomain = clean.isEmpty ? nil : clean
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    var linking = false

    /// Creates a tunnel; `done` gets the new row's id or the error.
    func link(_ request: Operations.LinkRequest, done: @escaping @MainActor (Result<String, CloudError>) -> Void) {
        linking = true
        Task {
            let result = await Task.detached { () -> Result<String, CloudError> in
                do { return .success(try Operations.link(request).hostname) } catch {
                    return .failure(CloudError(error.localizedDescription))
                }
            }.value
            self.inventory = await Task.detached { Inventory.load() }.value
            self.linking = false
            done(result)
        }
    }

    func rename(_ row: SiteRow, name: String, domain: String) {
        perform(row) { row in
            try Operations.rename(row, name: name.isEmpty ? nil : name, domain: domain.isEmpty ? nil : domain)
        }
    }

    func adopt(_ row: SiteRow) { perform(row) { try Operations.adopt($0) } }

    var cleaning = false

    /// Removes every tunnel, DNS record, config and LaunchAgent.
    func cleanAll() {
        cleaning = true
        Task {
            let failure = await Task.detached { () -> String? in
                var problems: [String] = []
                do {
                    try Operations.clean(try Operations.cleanPlan()) { if $0.hasPrefix("Couldn't") { problems.append($0) } }
                } catch { problems.append(error.localizedDescription) }
                return problems.isEmpty ? nil : problems.joined(separator: "\n")
            }.value
            self.error = failure
            self.inventory = await Task.detached { Inventory.load() }.value
            self.cleaning = false
        }
    }

    func deleteTunnel(_ row: SiteRow) {
        perform(row) { try Operations.unlink($0, deleteTunnel: true) }
    }
}
