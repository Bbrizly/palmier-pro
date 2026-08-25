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
        _ = try await FilmToolClient(executable: filmToolPath).run(
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
        _ = try await FilmToolClient(executable: filmToolPath).run(
            ["preflight", runManifest.path],
            environment: processEnvironment()
        )
    }
}
