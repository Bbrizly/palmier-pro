import FilmStudioCore
import Foundation

extension FilmStudioService {
    private struct AnimaticExportResponse: Decodable {
        let manifest: String
    }

    @concurrent
    static func exportAnimaticHandoff(
        runManifest: URL,
        filmToolExecutable: String
    ) async throws -> FilmAnimaticHandoff {
        try Task.checkCancellation()
        let filmTool = try FilmToolClient.resolveExecutable(filmToolExecutable)
        let result = try await FilmToolClient(executable: filmTool.path).run([
            "export-animatic",
            runManifest.standardizedFileURL.path,
        ])
        try Task.checkCancellation()

        guard let data = result.stdout.data(using: .utf8),
              let response = try? JSONDecoder().decode(AnimaticExportResponse.self, from: data) else {
            throw FilmStudioServiceError.invalidResponse("Film Tools did not return an Animatic handoff manifest.")
        }

        let manifestURL = URL(fileURLWithPath: response.manifest).standardizedFileURL
        let projectRoot = runManifest.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedManifest = manifestURL.resolvingSymlinksInPath()
        let rootPrefix = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        guard resolvedManifest.path.hasPrefix(rootPrefix) else {
            throw FilmStudioServiceError.invalidResponse("Film Tools returned a handoff outside the film project.")
        }

        let handoff = try FilmAnimaticHandoff.load(from: resolvedManifest)
        let declaredRun = try handoff.resolveRunManifest(relativeTo: resolvedManifest)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let requestedRun = runManifest.standardizedFileURL.resolvingSymlinksInPath()
        guard declaredRun == requestedRun else {
            throw FilmStudioServiceError.invalidResponse("The Animatic handoff belongs to a different film run.")
        }

        try validateHandoffMedia(handoff, handoffURL: resolvedManifest)
        return handoff
    }

    @concurrent
    private static func validateHandoffMedia(
        _ handoff: FilmAnimaticHandoff,
        handoffURL: URL
    ) throws {
        let fileManager = FileManager.default

        for asset in handoff.assets {
            let url = try handoff.resolveAsset(asset, relativeTo: handoffURL)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw FilmStudioServiceError.invalidResponse("Missing handoff asset: \(asset.relativePath)")
            }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue != asset.bytes {
                throw FilmStudioServiceError.invalidResponse("Handoff asset size changed after export: \(asset.relativePath)")
            }
        }

        for shot in handoff.orderedShots {
            guard let clipAssetID = shot.clipAssetId,
                  let clipAsset = handoff.asset(id: clipAssetID),
                  clipAsset.kind == "shot-clip" else {
                throw FilmStudioServiceError.invalidResponse(
                    "Shot \(shot.id) does not have a selected Film Studio clip yet. Complete production before opening the editable timeline."
                )
            }
        }
    }
}
