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

struct FilmStudioPluginManifest: Decodable, Sendable, Equatable {
    struct Command: Decodable, Sendable, Equatable {
        let name: String
    }

    let contractVersion: String
    let name: String
    let version: String
    let commands: [Command]

    var commandNames: Set<String> { Set(commands.map(\.name)) }
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
                && !$0.servingEngine.isEmpty
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
    let filmToolManifest: FilmStudioPluginManifest?
    let agentStatus: FilmStudioAgentStatus?
    let selectedAgentModel: FilmStudioAgentModel?
    let doctor: FilmStudioDoctorReport?
    let mereRunError: String?
    let filmToolError: String?
    let agentError: String?
    let doctorError: String?

    var mereRunReady: Bool { mereRunPath != nil && agentStatus != nil }
    var filmToolsReady: Bool { filmToolPath != nil && filmToolManifest != nil }
    var planningReady: Bool { mereRunReady && filmToolsReady }

    var piReady: Bool {
        if let pi = agentStatus?.pi,
           pi.installed,
           let path = pi.path,
           (try? FilmToolClient.resolveExecutable(path)) != nil {
            return true
        }
        return doctor?.check(named: "pi")?.ok == true
    }

    var ffmpegReady: Bool { doctor?.check(named: "ffmpeg")?.ok == true }
    var ffprobeReady: Bool { doctor?.check(named: "ffprobe")?.ok == true }
    var mediaToolsReady: Bool { ffmpegReady && ffprobeReady }
    var agentModelReady: Bool { selectedAgentModel != nil }

    var providerReady: Bool {
        guard let provider = agentStatus?.provider,
              provider.configured,
              let selectedAgentModel,
              provider.modelID == selectedAgentModel.id else { return false }
        let host = (provider.host ?? "127.0.0.1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let loopback = host.isEmpty
            || host == "localhost"
            || host == "::1"
            || host == "[::1]"
            || host.hasPrefix("127.")
        return loopback && (1...65_535).contains(provider.port ?? 8080)
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
    case incompatibleRuntime(String)
    case missingPi
    case missingAgentModel
    case missingAgentProvider(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let executable):
            "Required executable not found: \(executable)."
        case .incompatibleRuntime(let message):
            "Film Studio runtime is incompatible: \(message)"
        case .missingPi:
            "Pi is not installed or executable. Install it from Film Studio setup and retry."
        case .missingAgentModel:
            "No installed local producer model is ready for this Mac."
        case .missingAgentProvider(let modelID):
            "Pi's mere-run provider is not configured for \(modelID). Configure it from Film Studio setup and retry."
        case .invalidResponse(let message):
            "Film Studio returned an invalid response: \(message)"
        }
    }
}

enum FilmStudioService {
    private static let requiredFilmToolCommands: Set<String> = [
        "manifest",
        "doctor",
        "plan",
        "run",
        "recover",
        "brief",
        "approve",
        "configure",
        "preflight",
        "review-decision",
        "reroll",
        "export-animatic",
    ]

    private struct PlanResponse: Decodable {
        struct Status: Decodable {
            let runManifest: String
        }
        let status: Status
    }

    @concurrent
    static func loadProject(runManifest input: URL) async throws -> FilmStudioLoadedProject {
        try Task.checkCancellation()
        let snapshot = try FilmProjectLoader.load(runManifest: input)
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

        var filmToolManifest: FilmStudioPluginManifest?
        var compatibilityError: String?
        if let filmToolURL = filmToolResolution.url {
            do {
                let result = try await FilmToolClient(executable: filmToolURL.path).run(
                    ["manifest", "--json"],
                    environment: environment
                )
                let manifest = try decode(FilmStudioPluginManifest.self, from: result.stdout)
                try validateFilmToolManifest(manifest)
                filmToolManifest = manifest
            } catch {
                compatibilityError = error.localizedDescription
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
        let compatibleMereRunPath = agentStatus == nil ? nil : mereRunResolution.url?.path
        let compatibleFilmToolPath = filmToolManifest == nil ? nil : filmToolResolution.url?.path
        return FilmStudioRuntimeStatus(
            mereRunPath: compatibleMereRunPath,
            filmToolPath: compatibleFilmToolPath,
            filmToolManifest: filmToolManifest,
            agentStatus: agentStatus,
            selectedAgentModel: selectedAgentModel,
            doctor: doctor,
            mereRunError: mereRunResolution.error ?? (agentStatus == nil ? agentError : nil),
            filmToolError: filmToolResolution.error ?? compatibilityError,
            agentError: agentError,
            doctorError: doctorError
        )
    }

    @concurrent
    static func installFilmTools(mereRunExecutable: String) async throws {
        let mereRun = try requireCompatibleMereRun(mereRunExecutable)
        _ = try await FilmToolClient(executable: mereRun.path).run(
            ["plugin", "install", "mere-film-tools", "--yes"],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func installPi(mereRunExecutable: String) async throws {
        let mereRun = try requireCompatibleMereRun(mereRunExecutable)
        _ = try await FilmToolClient(executable: mereRun.path).run(
            ["agent", "install-pi"],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func configurePiProvider(mereRunExecutable: String, modelID: String) async throws {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FilmStudioServiceError.invalidResponse("A producer model id is required.")
        }
        let mereRun = try requireCompatibleMereRun(mereRunExecutable)
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
        let cleanIdea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIdea.isEmpty, !cleanTitle.isEmpty, durationSeconds > 0 else {
            throw FilmStudioServiceError.invalidResponse("Film idea, title, and a positive duration are required.")
        }
        let filmTool = try await requireCompatibleFilmTools(filmToolExecutable)
        let mereRun = try requireCompatibleMereRun(mereRunExecutable)
        let availableOutput = uniqueOutputDirectory(preferred: outputDirectory.standardizedFileURL)
        try FileManager.default.createDirectory(
            at: availableOutput.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var arguments = [
            "plan",
            "--idea", cleanIdea,
            "--title", cleanTitle,
            "--duration", String(durationSeconds),
            "--output-dir", availableOutput.path,
            "--mere-run-command", mereRun.path,
        ]
        if let status = try? await loadAgentStatus(mereRun: mereRun),
           status.pi.installed,
           let piPath = status.pi.path,
           let resolvedPi = try? FilmToolClient.resolveExecutable(piPath) {
            arguments.append(contentsOf: ["--pi-command", resolvedPi.path])
        }

        let result = try await FilmToolClient(executable: filmTool.path).run(
            arguments,
            environment: processEnvironment()
        )
        let response = try decode(PlanResponse.self, from: result.stdout)
        let rawRun = NSString(string: response.status.runManifest).expandingTildeInPath
        let runURL = rawRun.hasPrefix("/")
            ? URL(fileURLWithPath: rawRun)
            : availableOutput.appending(path: rawRun)
        let loaded = try FilmProjectLoader.load(runManifest: runURL)
        return loaded.runManifest
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
        let allowedUsage: Set<String> = ["personal", "noncommercial", "commercial"]
        guard allowedUsage.contains(usage),
              !audience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !tone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !rating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !references.isEmpty else {
            throw FilmStudioServiceError.invalidResponse("The confirmed film brief is incomplete.")
        }
        let filmTool = try await requireCompatibleFilmTools(filmToolExecutable)
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
        let allowedGates: Set<String> = ["brief", "treatment", "production", "picture-lock", "delivery"]
        guard allowedGates.contains(gate) else {
            throw FilmStudioServiceError.invalidResponse("Unknown Film Studio approval gate: \(gate)")
        }
        let filmTool = try await requireCompatibleFilmTools(filmToolExecutable)
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
        let filmTool = try await requireCompatibleFilmTools(filmToolExecutable)
        var environment = processEnvironment()
        environment["MERE_FILM_TOOLS_PI_PROVIDER"] = "mere-run"
        environment["MERE_FILM_TOOLS_PI_MODEL"] = context.model.id
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["run", runManifest.path, "--pi-command", context.piPath],
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
        let cleanShotID = shotID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanShotID.isEmpty, !cleanNote.isEmpty else {
            throw FilmStudioServiceError.invalidResponse("A shot id and revision note are required for a reroll.")
        }
        let filmTool = try await requireCompatibleFilmTools(filmToolExecutable)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["reroll", runManifest.path, "--shot", cleanShotID, "--note", cleanNote],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func recover(runManifest: URL, filmToolExecutable: String) async throws {
        let filmTool = try await requireCompatibleFilmTools(filmToolExecutable)
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
        let mereRun = try requireCompatibleMereRun(mereRunExecutable)
        let status = try await loadAgentStatus(mereRun: mereRun)
        guard status.pi.installed,
              let piPath = status.pi.path,
              let resolvedPi = try? FilmToolClient.resolveExecutable(piPath) else {
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
        return (resolvedPi.path, model)
    }

    private static func loadAgentStatus(mereRun: URL) async throws -> FilmStudioAgentStatus {
        let result = try await FilmToolClient(executable: mereRun.path).run(
            ["agent", "status", "--json"],
            environment: processEnvironment()
        )
        return try decode(FilmStudioAgentStatus.self, from: result.stdout)
    }

    private static func requireCompatibleMereRun(_ value: String) throws -> URL {
        let url = try requireExecutable(value)
        return url
    }

    @concurrent
    private static func requireCompatibleFilmTools(_ value: String) async throws -> URL {
        let url = try requireExecutable(value)
        let result = try await FilmToolClient(executable: url.path).run(
            ["manifest", "--json"],
            environment: processEnvironment()
        )
        let manifest = try decode(FilmStudioPluginManifest.self, from: result.stdout)
        try validateFilmToolManifest(manifest)
        return url
    }

    private static func validateFilmToolManifest(_ manifest: FilmStudioPluginManifest) throws {
        guard manifest.contractVersion == "mere.run/plugin.v1", manifest.name == "mere-film-tools" else {
            throw FilmStudioServiceError.incompatibleRuntime(
                "expected mere-film-tools with mere.run/plugin.v1, found \(manifest.name) / \(manifest.contractVersion)."
            )
        }
        let missing = requiredFilmToolCommands.subtracting(manifest.commandNames).sorted()
        guard missing.isEmpty else {
            throw FilmStudioServiceError.incompatibleRuntime(
                "the installed mere-film-tools \(manifest.version) is missing required commands: \(missing.joined(separator: ", ")). Update Film Studio tools and retry."
            )
        }
    }

    private static func requireExecutable(_ value: String) throws -> URL {
        do {
            return try FilmToolClient.resolveExecutable(value)
        } catch {
            throw FilmStudioServiceError.missingExecutable(value)
        }
    }

    private static func resolveExecutable(_ value: String) -> (url: URL?, error: String?) {
        do {
            return (try FilmToolClient.resolveExecutable(value), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private static func uniqueOutputDirectory(preferred: URL) -> URL {
        guard FileManager.default.fileExists(atPath: preferred.path) else { return preferred }
        let parent = preferred.deletingLastPathComponent()
        let base = preferred.lastPathComponent
        var index = 2
        while index < Int.max {
            let candidate = parent.appending(path: "\(base)-\(index)", directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
        return parent.appending(path: "\(base)-\(UUID().uuidString)", directoryHint: .isDirectory)
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
