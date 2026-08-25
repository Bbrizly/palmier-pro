import Foundation

public enum FilmProjectError: LocalizedError, Equatable {
    case missingRunManifest(URL)
    case missingProject(URL)
    case unsupportedContract(String)
    case invalidProject(String)

    public var errorDescription: String? {
        switch self {
        case .missingRunManifest(let url):
            "No run.json exists at \(url.path)."
        case .missingProject(let url):
            "No film-project.json exists at \(url.path)."
        case .unsupportedContract(let version):
            "Unsupported film contract: \(version)."
        case .invalidProject(let message):
            "The film project could not be read: \(message)"
        }
    }
}

public enum FilmProjectLoader {
    private struct WorkspaceFiles {
        let run: URL
        let root: URL

        init(_ input: URL) {
            run = input.standardizedFileURL
            root = run.deletingLastPathComponent()
        }

        var project: URL { root.appending(path: "film-project.json") }
        var productionPlan: URL { root.appending(path: "production-plan.json") }
        var treatment: URL { root.appending(path: "treatment.json") }
    }

    public static func load(runManifest: URL) throws -> FilmWorkspaceSnapshot {
        let files = WorkspaceFiles(runManifest)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: files.run.path) else {
            throw FilmProjectError.missingRunManifest(files.run)
        }
        guard fileManager.fileExists(atPath: files.project.path) else {
            throw FilmProjectError.missingProject(files.project)
        }

        do {
            let project: FilmProject = try read(files.project)
            guard project.contractVersion == "mere.run/film-project.v1" else {
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

    private static func read<Value: Decodable>(_ url: URL) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private static func readOptional<Value: Decodable>(_ url: URL) throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try read(url)
    }
}
