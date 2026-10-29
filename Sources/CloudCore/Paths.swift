import Foundation

public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser.path
    public static let cloudflared = "\(home)/.cloudflared"
    public static let launchAgents = "\(home)/Library/LaunchAgents"
    public static let logs = "\(home)/Library/Logs/tunnel"
    public static let settings = "\(home)/.config/tunnel/settings.json"
}
