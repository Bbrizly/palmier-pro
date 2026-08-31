import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ProcessResult: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

public enum FilmToolError: LocalizedError, Equatable {
    case executableNotFound(String)
    case launchFailed(String)
    case commandFailed(ProcessResult)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            "Required executable not found: \(name)"
        case .launchFailed(let message):
            "Could not launch film command: \(message)"
        case .commandFailed(let result):
            result.stderr.isEmpty
                ? "Film command exited \(result.exitCode)."
                : result.stderr
        }
    }
}

public struct FilmToolClient: Sendable {
    public let executable: String

    public init(executable: String = "mere-film-tools") {
        self.executable = executable
    }

    @concurrent
    public func run(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let executableURL = try Self.resolveExecutable(executable)
        return try await Self.runProcess(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment
        )
    }

    public static func resolveExecutable(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FilmToolError.executableNotFound(value)
        }

        if trimmed.contains("/") || trimmed.hasPrefix("~") {
            let expanded = NSString(string: trimmed).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw FilmToolError.executableNotFound(value)
            }
            return url
        }

        let fileManager = FileManager.default
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let standardDirectories = [
            fileManager.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for directory in standardDirectories where !directories.contains(directory) {
            directories.append(directory)
        }

        for directory in directories {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appending(path: trimmed)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url.standardizedFileURL
            }
        }

        throw FilmToolError.executableNotFound(value)
    }

    @concurrent
    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appending(path: "palmier-film-tool-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let stdoutURL = temporaryDirectory.appending(path: "stdout")
        let stderrURL = temporaryDirectory.appending(path: "stderr")
        guard fileManager.createFile(atPath: stdoutURL.path, contents: nil),
              fileManager.createFile(atPath: stderrURL.path, contents: nil) else {
            throw FilmToolError.launchFailed("Could not create process output files.")
        }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        var handlesClosed = false
        defer {
            if !handlesClosed {
                try? stdoutHandle.close()
                try? stderrHandle.close()
            }
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw FilmToolError.launchFailed(error.localizedDescription)
        }

        do {
            while process.isRunning {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            await terminate(process)
            throw error
        }

        try stdoutHandle.close()
        try stderrHandle.close()
        handlesClosed = true

        let stdout = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let result = ProcessResult(
            executable: executableURL.path,
            arguments: arguments,
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
        guard result.succeeded else {
            throw FilmToolError.commandFailed(result)
        }
        return result
    }

    @concurrent
    private static func terminate(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<20 {
            if !process.isRunning { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard process.isRunning else { return }
        #if canImport(Darwin)
        _ = Darwin.kill(process.processIdentifier, SIGKILL)
        #elseif canImport(Glibc)
        _ = Glibc.kill(process.processIdentifier, SIGKILL)
        #endif
        for _ in 0..<10 {
            if !process.isRunning { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
