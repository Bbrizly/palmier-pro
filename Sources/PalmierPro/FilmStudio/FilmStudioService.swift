import Darwin
import FilmStudioCore
import Foundation

struct FilmStudioLoadedProject: Sendable {
    let snapshot: FilmWorkspaceSnapshot
    let playableCutURL: URL?
}

struct FilmStudioDoctorCheck: Decodable, Sendable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let ok: Bool
    let required: Bool
    let detail: String
}

struct FilmStudioDoctorReport: Decodable, Sendable, Equatable {
    let ok: Bool
    let checks: [FilmStudioDoctorCheck]
    let note: String?

    func check(named name: String) -> FilmStudioDoctorCheck? {
        checks.first { $0.name == name }
    }
}

struct FilmStudioAgentMachine: Decodable, Sendable, Equatable {
    let processor: String
    let unifiedMemoryGB: Int
    let appleSiliconMac: Bool
    let linux: Bool
}

struct FilmStudioAgentPi: Decodable, Sendable, Equatable {
    let installed: Bool
    let managedInstall: Bool
    let autoInstallSupported: Bool
    let path: String?
    let version: String?
}

struct FilmStudioAgentProvider: Decodable, Sendable, Equatable {
    let configured: Bool
    let host: String?
    let port: Int?
    let modelID: String?
}

struct FilmStudioAgentModel: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let summary: String
    let minimumUnifiedMemoryGB: Int
    let recommendedUnifiedMemoryGB: Int
    let servingEngine: String
    let startableByMereRun: Bool
    let sourceConfigurationRequired: Bool
    let installed: Bool
    let reason: String?
}

struct FilmStudioAgentStatus: Decodable, Sendable, Equatable {
    let machine: FilmStudioAgentMachine
    let pi: FilmStudioAgentPi
    let provider: FilmStudioAgentProvider
    let recommendedModelID: String?
    let models: [FilmStudioAgentModel]
}

enum FilmStudioAgentSelector {
    static func select(from status: FilmStudioAgentStatus) -> FilmStudioAgentModel? {
        let eligible = status.models.filter {
            $0.installed
                && $0.startableByMereRun
                && $0.minimumUnifiedMemoryGB <= status.machine.unifiedMemoryGB
        }
        if let recommendedModelID = status.recommendedModelID,
           let recommended = eligible.first(where: { $0.id == recommendedModelID }) {
            return recommended
        }
        return eligible.max {
            if $0.recommendedUnifiedMemoryGB == $1.recommendedUnifiedMemoryGB {
                return $0.id < $1.id
            }
            return $0.recommendedUnifiedMemoryGB < $1.recommendedUnifiedMemoryGB
        }
    }
}

struct FilmStudioRuntimeStatus: Sendable, Equatable {
    let mereRunPath: String?
    let filmToolPath: String?
    let agentStatus: FilmStudioAgentStatus?
    let selectedAgentModel: FilmStudioAgentModel?
    let doctor: FilmStudioDoctorReport?
    let mereRunError: String?
    let filmToolError: String?
    let agentError: String?
    let doctorError: String?

    var mereRunReady: Bool { mereRunPath != nil }
    var filmToolsReady: Bool { filmToolPath != nil }
    var planningReady: Bool { mereRunReady && filmToolsReady }

    var piReady: Bool {
        if let pi = agentStatus?.pi { return pi.installed && pi.path != nil }
        return doctor?.check(named: "pi")?.ok == true
    }

    var ffmpegReady: Bool { doctor?.check(named: "ffmpeg")?.ok == true }
    var ffprobeReady: Bool { doctor?.check(named: "ffprobe")?.ok == true }
    var mediaToolsReady: Bool { ffmpegReady && ffprobeReady }
    var agentModelReady: Bool { selectedAgentModel != nil }

    var providerReady: Bool {
        guard let provider = agentStatus?.provider,
              provider.configured,
              let selectedAgentModel else { return false }
        return provider.modelID == selectedAgentModel.id
    }

    var agentReady: Bool {
        planningReady && piReady && agentModelReady && providerReady
    }

    var productionReady: Bool {
        agentReady && mediaToolsReady
    }

    var recommendedModel: FilmStudioAgentModel? {
        guard let recommendedModelID = agentStatus?.recommendedModelID else { return nil }
        return agentStatus?.models.first { $0.id == recommendedModelID }
    }
}

enum FilmStudioServiceError: LocalizedError {
    case missingExecutable(String)
    case missingPi
    case missingAgentModel
    case missingAgentProvider(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let executable):
            "Required executable not found: \(executable)."
        case .missingPi:
            "Pi is not installed. Install it from Film Studio setup and retry."
        case .missingAgentModel:
            "No installed local agent model is ready for this Mac."
        case .missingAgentProvider(let modelID):
            "Pi's mere-run provider is not configured for \(modelID). Configure it from Film Studio setup and retry."
        case .invalidResponse(let message):
            "Film Studio returned an invalid response: \(message)"
        }
    }
}

enum FilmStudioService {
    private struct PlanResponse: Decodable {
        struct Status: Decodable {
            let runManifest: String
        }
        let status: Status
    }

    @concurrent
    static func loadProject(runManifest input: URL) async throws -> FilmStudioLoadedProject {
        try Task.checkCancellation()
        let runManifest = input.lastPathComponent == "run.json"
            ? input.standardizedFileURL
            : input.appending(path: "run.json").standardizedFileURL
        let snapshot = try FilmProjectLoader.load(runManifest: runManifest)
        try Task.checkCancellation()
        return FilmStudioLoadedProject(snapshot: snapshot, playableCutURL: snapshot.playableCutURL)
    }

    @concurrent
    static func inspectRuntime(
        filmToolExecutable: String,
        mereRunExecutable: String
    ) async -> FilmStudioRuntimeStatus {
        let environment = processEnvironment()
        let mereRunResolution = resolveExecutable(mereRunExecutable)
        let filmToolResolution = resolveExecutable(filmToolExecutable)

        var agentStatus: FilmStudioAgentStatus?
        var agentError: String?
        if let mereRunURL = mereRunResolution.url {
            do {
                let result = try await FilmToolClient(executable: mereRunURL.path).run(
                    ["agent", "status", "--json"],
                    environment: environment
                )
                agentStatus = try decode(FilmStudioAgentStatus.self, from: result.stdout)
            } catch {
                agentError = error.localizedDescription
            }
        }

        var doctor: FilmStudioDoctorReport?
        var doctorError: String?
        if let filmToolURL = filmToolResolution.url {
            var arguments = ["doctor"]
            if let mereRunURL = mereRunResolution.url {
                arguments.append(contentsOf: ["--mere-run-command", mereRunURL.path])
            }
            do {
                let result = try await FilmToolClient(executable: filmToolURL.path).run(
                    arguments,
                    environment: environment
                )
                doctor = try decode(FilmStudioDoctorReport.self, from: result.stdout)
            } catch FilmToolError.commandFailed(let result) {
                do {
                    doctor = try decode(FilmStudioDoctorReport.self, from: result.stdout)
                } catch {
                    doctorError = result.stderr.isEmpty ? error.localizedDescription : result.stderr
                }
            } catch {
                doctorError = error.localizedDescription
            }
        }

        let selectedAgentModel = agentStatus.flatMap(FilmStudioAgentSelector.select)
        return FilmStudioRuntimeStatus(
            mereRunPath: mereRunResolution.url?.path,
            filmToolPath: filmToolResolution.url?.path,
            agentStatus: agentStatus,
            selectedAgentModel: selectedAgentModel,
            doctor: doctor,
            mereRunError: mereRunResolution.error,
            filmToolError: filmToolResolution.error,
            agentError: agentError,
            doctorError: doctorError
        )
    }

    @concurrent
    static func installFilmTools(mereRunExecutable: String) async throws {
        let mereRun = try requireExecutable(mereRunExecutable)
        _ = try await FilmToolClient(executable: mereRun.path).run(
            ["plugin", "install", "mere-film-tools", "--yes"],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func installPi(mereRunExecutable: String) async throws {
        let mereRun = try requireExecutable(mereRunExecutable)
        _ = try await FilmToolClient(executable: mereRun.path).run(
            ["agent", "install-pi"],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func configurePiProvider(mereRunExecutable: String, modelID: String) async throws {
        let mereRun = try requireExecutable(mereRunExecutable)
        _ = try await FilmToolClient(executable: mereRun.path).run(
            ["agent", "onboard", "--configure-pi", "--model", modelID],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func createFilm(
        idea: String,
        title: String,
        durationSeconds: Int,
        outputDirectory: URL,
        filmToolExecutable: String,
        mereRunExecutable: String
    ) async throws -> URL {
        try Task.checkCancellation()
        let filmTool = try requireExecutable(filmToolExecutable)
        let mereRun = try requireExecutable(mereRunExecutable)
        let availableOutput = uniqueOutputDirectory(preferred: outputDirectory)
        try FileManager.default.createDirectory(
            at: availableOutput.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var arguments = [
            "plan",
            "--idea", idea,
            "--title", title,
            "--duration", String(durationSeconds),
            "--output-dir", availableOutput.path,
            "--mere-run-command", mereRun.path,
        ]
        if let status = try? await loadAgentStatus(mereRun: mereRun),
           status.pi.installed,
           let piPath = status.pi.path {
            arguments.append(contentsOf: ["--pi-command", piPath])
        }

        let result = try await FilmToolClient(executable: filmTool.path).run(
            arguments,
            environment: processEnvironment()
        )
        let response = try decode(PlanResponse.self, from: result.stdout)
        return URL(fileURLWithPath: response.status.runManifest)
    }

    @concurrent
    static func updateBrief(
        runManifest: URL,
        audience: String,
        genre: String,
        tone: String,
        rating: String,
        usage: String,
        references: [String],
        filmToolExecutable: String
    ) async throws {
        let filmTool = try requireExecutable(filmToolExecutable)
        var arguments = [
            "brief", runManifest.path,
            "--audience", audience,
            "--genre", genre,
            "--tone", tone,
            "--rating", rating,
            "--usage", usage,
        ]
        for reference in references {
            arguments.append(contentsOf: ["--reference", reference])
        }
        _ = try await FilmToolClient(executable: filmTool.path).run(
            arguments,
            environment: processEnvironment()
        )
    }

    @concurrent
    static func approve(
        runManifest: URL,
        gate: String,
        approvedBy: String,
        filmToolExecutable: String
    ) async throws {
        let filmTool = try requireExecutable(filmToolExecutable)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            [
                "approve", runManifest.path,
                "--gate", gate,
                "--note", "Approved in Palmier Pro after reviewing the current GRACE evidence.",
                "--approved-by", approvedBy,
            ],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func advance(
        runManifest: URL,
        filmToolExecutable: String,
        mereRunExecutable: String
    ) async throws {
        let context = try await agentContext(mereRunExecutable: mereRunExecutable)
        let filmTool = try requireExecutable(filmToolExecutable)
        var environment = processEnvironment()
        environment["MERE_FILM_TOOLS_PI_PROVIDER"] = "mere-run"
        environment["MERE_FILM_TOOLS_PI_MODEL"] = context.model.id
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["run", runManifest.path, "--pi-command", context.piPath],
            environment: environment
        )
    }

    @concurrent
    static func review(
        runManifest: URL,
        filmToolExecutable: String,
        mereRunExecutable: String
    ) async throws {
        let context = try await agentContext(mereRunExecutable: mereRunExecutable)
        let filmTool = try requireExecutable(filmToolExecutable)
        var environment = processEnvironment()
        environment["MERE_FILM_TOOLS_PI_PROVIDER"] = "mere-run"
        environment["MERE_FILM_TOOLS_PI_MODEL"] = context.model.id
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["review", runManifest.path, "--pi-command", context.piPath],
            environment: environment
        )
    }

    @concurrent
    static func reroll(
        runManifest: URL,
        shotID: String,
        note: String,
        filmToolExecutable: String
    ) async throws {
        let filmTool = try requireExecutable(filmToolExecutable)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["reroll", runManifest.path, "--shot", shotID, "--note", note],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func recover(runManifest: URL, filmToolExecutable: String) async throws {
        let filmTool = try requireExecutable(filmToolExecutable)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["recover", runManifest.path],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func makeWatcher(
        root: URL,
        onChange: @escaping @Sendable () -> Void
    ) async -> FilmStudioProjectWatcher? {
        FilmStudioProjectWatcher(root: root, onChange: onChange)
    }

    static func modelSetupCommand(runtime: FilmStudioRuntimeStatus, mereRunExecutable: String) -> String {
        let mereRun = runtime.mereRunPath ?? mereRunExecutable
        if let model = runtime.recommendedModel {
            return "\(shellQuote(mereRun)) model pull \(shellQuote(model.id))"
        }
        return "\(shellQuote(mereRun)) agent onboard"
    }

    static func stopManagedAgentServer() async {
        await FilmStudioAgentServer.shared.stop()
    }

    private static func agentContext(
        mereRunExecutable: String
    ) async throws -> (piPath: String, model: FilmStudioAgentModel) {
        let mereRun = try requireExecutable(mereRunExecutable)
        let status = try await loadAgentStatus(mereRun: mereRun)
        guard status.pi.installed, let piPath = status.pi.path else {
            throw FilmStudioServiceError.missingPi
        }
        guard let model = FilmStudioAgentSelector.select(from: status) else {
            throw FilmStudioServiceError.missingAgentModel
        }
        guard status.provider.configured, status.provider.modelID == model.id else {
            throw FilmStudioServiceError.missingAgentProvider(model.id)
        }
        try await FilmStudioAgentServer.shared.ensureRunning(
            mereRun: mereRun,
            status: status,
            model: model,
            environment: processEnvironment()
        )
        return (piPath, model)
    }

    private static func loadAgentStatus(mereRun: URL) async throws -> FilmStudioAgentStatus {
        let result = try await FilmToolClient(executable: mereRun.path).run(
            ["agent", "status", "--json"],
            environment: processEnvironment()
        )
        return try decode(FilmStudioAgentStatus.self, from: result.stdout)
    }

    private static func requireExecutable(_ value: String) throws -> URL {
        let resolution = resolveExecutable(value)
        guard let url = resolution.url else {
            throw FilmStudioServiceError.missingExecutable(value)
        }
        return url
    }

    private static func resolveExecutable(_ value: String) -> (url: URL?, error: String?) {
        if let resolved = try? FilmToolClient.resolveExecutable(value) {
            return (resolved, nil)
        }
        guard !value.contains("/") else {
            return (nil, "Required executable not found: \(value)")
        }
        let homeLocal = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/bin")
            .appending(path: value)
        if FileManager.default.isExecutableFile(atPath: homeLocal.path) {
            return (homeLocal, nil)
        }
        return (nil, "Required executable not found: \(value)")
    }

    private static func uniqueOutputDirectory(preferred: URL) -> URL {
        guard FileManager.default.fileExists(atPath: preferred.path) else { return preferred }
        let parent = preferred.deletingLastPathComponent()
        let base = preferred.lastPathComponent
        var index = 2
        while true {
            let candidate = parent.appending(path: "\(base)-\(index)", directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    static func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var pathComponents = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let additions = [
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for addition in additions where !pathComponents.contains(addition) {
            pathComponents.append(addition)
        }
        environment["PATH"] = pathComponents.joined(separator: ":")
        return environment
    }

    private static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: Data(text.utf8))
        } catch {
            throw FilmStudioServiceError.invalidResponse(error.localizedDescription)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

final class FilmStudioProjectWatcher: @unchecked Sendable {
    private let descriptor: CInt
    private let source: DispatchSourceFileSystemObject

    init?(root: URL, onChange: @escaping @Sendable () -> Void) {
        descriptor = open(root.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: DispatchQueue(label: "io.palmier.film-studio-watcher", qos: .utility)
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }
}
