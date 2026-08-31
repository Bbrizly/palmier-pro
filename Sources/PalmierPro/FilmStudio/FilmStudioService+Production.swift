import FilmStudioCore
import Foundation

extension FilmStudioService {
    @concurrent
    static func configureProduction(
        runManifest: URL,
        mode: String,
        takesPerShot: Int,
        filmToolPath: String
    ) async throws {
        guard mode == "draft" || mode == "final" else {
            throw FilmStudioServiceError.invalidResponse("Production mode must be draft or final.")
        }
        guard 1...4 ~= takesPerShot else {
            throw FilmStudioServiceError.invalidResponse("Takes per shot must be between 1 and 4.")
        }
        let filmTool = try await FilmStudioRuntimeCompatibility.requireFilmTools(filmToolPath)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            [
                "configure", runManifest.path,
                "--mode", mode,
                "--takes-per-shot", String(takesPerShot),
            ],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func preflightProduction(
        runManifest: URL,
        filmToolPath: String
    ) async throws {
        let filmTool = try await FilmStudioRuntimeCompatibility.requireFilmTools(filmToolPath)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["preflight", runManifest.path],
            environment: processEnvironment()
        )
    }

    @concurrent
    static func advanceWithoutAgent(
        runManifest: URL,
        filmToolPath: String
    ) async throws {
        let filmTool = try await FilmStudioRuntimeCompatibility.requireFilmTools(filmToolPath)
        _ = try await FilmToolClient(executable: filmTool.path).run(
            ["run", runManifest.path],
            environment: processEnvironment()
        )
    }
}
