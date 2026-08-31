import FilmStudioCore
import Foundation

enum FilmStudioRuntimeCompatibility {
    static let requiredFilmToolCommands: Set<String> = [
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

    @concurrent
    static func requireFilmTools(_ executable: String) async throws -> URL {
        let url: URL
        do {
            url = try FilmToolClient.resolveExecutable(executable)
        } catch {
            throw FilmStudioServiceError.missingExecutable(executable)
        }

        let result = try await FilmToolClient(executable: url.path).run(
            ["manifest", "--json"],
            environment: FilmStudioService.processEnvironment()
        )
        let manifest: FilmStudioPluginManifest
        do {
            manifest = try JSONDecoder().decode(FilmStudioPluginManifest.self, from: Data(result.stdout.utf8))
        } catch {
            throw FilmStudioServiceError.incompatibleRuntime(
                "mere-film-tools did not return a valid plugin manifest: \(error.localizedDescription)"
            )
        }

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
        return url
    }
}
