import Foundation

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

        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let url = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appending(path: trimmed)
            if FileManager.default.isExecutableFile(atPath: url.path) {
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
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
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
            if process.isRunning {
                process.terminate()
            }
            throw error
        }

        try stdoutHandle.close()
        try stderrHandle.close()

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
}
