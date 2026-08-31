import FilmStudioCore
import Foundation

extension FilmStudioService {
    @concurrent
    static func exportAnimaticHandoff(
        runManifest: URL,
        filmToolExecutable: String
    ) async throws -> FilmAnimaticHandoff {
        try Task.checkCancellation()
        let filmTool = try FilmToolClient.resolveExecutable(filmToolExecutable)
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "palmier-film-handoff-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        _ = try await FilmToolClient(executable: filmTool.path).run([
            "export-animatic",
            runManifest.standardizedFileURL.path,
            "--output",
            outputURL.path,
        ])
        try Task.checkCancellation()

        let handoff = try FilmAnimaticHandoff.load(from: outputURL)
        try validateHandoffMedia(handoff, runManifest: runManifest)
        return handoff
    }

    @concurrent
    private static func validateHandoffMedia(
        _ handoff: FilmAnimaticHandoff,
        runManifest: URL
    ) throws {
        let fileManager = FileManager.default
        for shot in handoff.orderedShots {
            let url = handoff.resolve(shot.clipPath, relativeTo: runManifest)
            guard fileManager.fileExists(atPath: url.path) else {
                throw FilmStudioServiceError.invalidResponse(
                    "Missing current take for \(shot.shotId): \(shot.clipPath)"
                )
            }
        }

        let optionalPaths = [
            handoff.media.dialogueBed,
            handoff.media.musicBed,
            handoff.media.effectsBed,
            handoff.media.deliveryMaster,
            handoff.media.roughCut,
        ].compactMap { $0 }
        for path in optionalPaths {
            let url = handoff.resolve(path, relativeTo: runManifest)
            guard fileManager.fileExists(atPath: url.path) else {
                throw FilmStudioServiceError.invalidResponse("Missing handoff media: \(path)")
            }
        }
    }
}