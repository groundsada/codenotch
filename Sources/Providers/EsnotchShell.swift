import Foundation

/// A subprocess that answers with stdout — the only plumbing the ESnet/LBL
/// providers need. `vpnctl` and the spend fetchers are plain executables, so
/// there is no session to hold and no credential to read; the timeout kills a
/// wedged helper rather than holding a ring open.
enum EsnotchShell {
    /// Long enough for `vpnctl status` to answer even with a slow ping probe,
    /// short enough that a wedged helper cannot hold a refresh open.
    static let timeout: TimeInterval = 15

    static func capture(executable: URL, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        // Discarded, not piped: a pipe nobody reads fills at 64 KB and stalls
        // the helper until the watchdog kills it.
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility)
            .asyncAfter(deadline: .now() + timeout, execute: watchdog)
        defer { watchdog.cancel() }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UsageProviderError.badResponse(status: Int(process.terminationStatus))
        }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw UsageProviderError.badResponse(status: 0)
        }
        return text
    }

    /// A helper script by absolute path. Finder launches this app with a
    /// stripped `PATH`, so nothing is discovered — the path is spelled out.
    static func captureScript(path: String, arguments: [String] = []) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else {
            throw UsageProviderError.badResponse(status: 404)
        }
        return try capture(executable: URL(fileURLWithPath: expanded), arguments: arguments)
    }

    /// Runs a helper on the cooperative pool: reading the pipe to exhaustion
    /// blocks the thread it is on, and the caller is an actor whose other work
    /// must not sit behind it.
    static func run(_ operation: @escaping @Sendable () throws -> String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result { try operation() })
            }
        }
    }

    static func readJSON(path: String) throws -> Data {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.isReadableFile(atPath: expanded) else {
            throw UsageProviderError.badResponse(status: 404)
        }
        return try Data(contentsOf: URL(fileURLWithPath: expanded))
    }
}
