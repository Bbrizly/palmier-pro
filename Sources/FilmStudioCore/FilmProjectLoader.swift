import Foundation

public enum FilmProjectError: LocalizedError, Equatable {
    case missingRunManifest(URL)
    case missingProject(URL)
    case unsupportedRunContract(String)
    case unsupportedContract(String)
    case invalidRunManifest(String)
    case invalidProject(String)

    public var errorDescription: String? {
        switch self {
        case .missingRunManifest(let url):
            "No GRACE run manifest exists at \(url.path)."
        case .missingProject(let url):
            "No film-project.json exists at \(url.path)."
        case .unsupportedRunContract(let version):
            "Unsupported GRACE run contract: \(version)."
        case .unsupportedContract(let version):
            "Unsupported film contract: \(version)."
        case .invalidRunManifest(let message):
            "The GRACE run manifest could not be read: \(message)"
        case .invalidProject(let message):
            "The film project could not be read: \(message)"
        }
    }
}

public enum FilmProjectLoader {
    private static let supportedRunContract = "mere.run/plugin-run.v1"
    private static let supportedProjectContract = "mere.run/film-project.v1"

    private struct RunManifest: Decodable {
        struct Local: Decodable {
            let outputDirectory: String
            let projectManifest: String
        }

        let contractVersion: String
        let local: Local
    }

    private struct WorkspaceFiles {
        let run: URL
        let root: URL
        let project: URL

        var productionPlan: URL { root.appending(path: "production-plan.json") }
        var treatment: URL { root.appending(path: "treatment.json") }
    }

    public static func load(runManifest input: URL) throws -> FilmWorkspaceSnapshot {
        let fileManager = FileManager.default
        let run = input.standardizedFileURL.resolvingSymlinksInPath()
        guard fileManager.fileExists(atPath: run.path) else {
            throw FilmProjectError.missingRunManifest(run)
        }

        let manifest: RunManifest
        do {
            manifest = try read(run)
        } catch {
            throw FilmProjectError.invalidRunManifest(error.localizedDescription)
        }
        guard manifest.contractVersion == supportedRunContract else {
            throw FilmProjectError.unsupportedRunContract(manifest.contractVersion)
        }

        let files = try workspaceFiles(run: run, manifest: manifest)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: files.root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FilmProjectError.invalidRunManifest(
                "local.outputDirectory does not resolve to a film workspace: \(files.root.path)"
            )
        }
        guard fileManager.fileExists(atPath: files.project.path) else {
            throw FilmProjectError.missingProject(files.project)
        }

        do {
            let project: FilmProject = try read(files.project)
            guard project.contractVersion == supportedProjectContract else {
                throw FilmProjectError.unsupportedContract(project.contractVersion)
            }

            return FilmWorkspaceSnapshot(
                root: files.root,
                runManifest: files.run,
                project: project,
                productionPlan: try readOptional(files.productionPlan),
                treatment: try readOptional(files.treatment)
            )
        } catch let error as FilmProjectError {
            throw error
        } catch {
            throw FilmProjectError.invalidProject(error.localizedDescription)
        }
    }

    private static func workspaceFiles(run: URL, manifest: RunManifest) throws -> WorkspaceFiles {
        let runDirectory = run.deletingLastPathComponent()
        let root = resolvePath(manifest.local.outputDirectory, relativeTo: runDirectory)
        let project = resolvePath(manifest.local.projectManifest, relativeTo: runDirectory)
        let expectedProject = root.appending(path: "film-project.json")
            .standardizedFileURL
            .resolvingSymlinksInPath()

        guard project == expectedProject else {
            throw FilmProjectError.invalidRunManifest(
                "local.projectManifest must resolve to the workspace film-project.json."
            )
        }
        return WorkspaceFiles(run: run, root: root, project: project)
    }

    private static func resolvePath(_ rawValue: String, relativeTo base: URL) -> URL {
        let expanded = NSString(string: rawValue).expandingTildeInPath
        let candidate = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : base.appending(path: expanded)
        return candidate.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func read<Value: Decodable>(_ url: URL) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private static func readOptional<Value: Decodable>(_ url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url)
    }
}
