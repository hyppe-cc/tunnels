import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public var ok: Bool { status == 0 }
}

public struct ShellError: LocalizedError, Sendable {
    public let command: String
    public let result: ShellResult
    public var errorDescription: String? {
        let detail = result.stderr.isEmpty ? result.stdout : result.stderr
        return "`\(command)` failed (\(result.status)): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

public enum Shell {
    /// Apps launched from Finder get a minimal PATH, so tools are resolved against the usual install locations.
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    public static func which(_ tool: String) -> String? {
        if tool.hasPrefix("/") { return tool }
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in searchPaths + envPaths {
            let path = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    @discardableResult
    public static func run(_ tool: String, _ args: [String]) -> ShellResult {
        guard let path = which(tool) else {
            return ShellResult(status: 127, stdout: "", stderr: "\(tool): not found")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            return ShellResult(status: 126, stdout: "", stderr: error.localizedDescription)
        }
        // Read before waiting so a full pipe buffer can't deadlock the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    /// Runs and throws on a non-zero exit.
    @discardableResult
    public static func check(_ tool: String, _ args: [String]) throws -> ShellResult {
        let result = run(tool, args)
        guard result.ok else { throw ShellError(command: ([tool] + args).joined(separator: " "), result: result) }
        return result
    }
}
