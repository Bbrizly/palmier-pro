import CryptoKit
import FilmStudioCore
import Foundation

extension FilmStudioService {
    private struct AnimaticExportResponse: Decodable {
        let manifest: String
        let manifestSha256: String
        let projectId: String
        let shots: Int
        let assets: Int
        let bytes: Int
    }

    @concurrent
    static func exportAnimaticHandoff(
        runManifest: URL,
        filmToolExecutable: String
    ) async throws -> FilmAnimaticHandoff {
        try Task.checkCancellation()
        let workspace = try FilmProjectLoader.load(runManifest: runManifest)
        let filmTool = try FilmToolClient.resolveExecutable(filmToolExecutable)
        let result = try await FilmToolClient(executable: filmTool.path).run([
            "export-animatic",
            workspace.runManifest.path,
        ])
        try Task.checkCancellation()

        guard let data = result.stdout.data(using: .utf8),
              let response = try? JSONDecoder().decode(AnimaticExportResponse.self, from: data) else {
            throw FilmStudioServiceError.invalidResponse("Film Tools did not return a complete Animatic handoff receipt.")
        }

        let manifestURL = URL(fileURLWithPath: response.manifest).standardizedFileURL
        let projectRoot = workspace.root.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedManifest = manifestURL.resolvingSymlinksInPath()
        let rootPrefix = projectRoot.path.hasSuffix("/") ? projectRoot.path : projectRoot.path + "/"
        guard resolvedManifest.path.hasPrefix(rootPrefix) else {
            throw FilmStudioServiceError.invalidResponse("Film Tools returned a handoff outside the film project.")
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedManifest.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw FilmStudioServiceError.invalidResponse("Film Tools returned a handoff manifest that does not exist.")
        }
        let manifestAttributes = try fileManager.attributesOfItem(atPath: resolvedManifest.path)
        guard let manifestSize = manifestAttributes[.size] as? NSNumber,
              manifestSize.intValue == response.bytes else {
            throw FilmStudioServiceError.invalidResponse("The Animatic handoff manifest changed after export.")
        }
        let manifestHash = try sha256(of: resolvedManifest)
        guard manifestHash == response.manifestSha256 else {
            throw FilmStudioServiceError.invalidResponse("The Animatic handoff manifest failed its SHA-256 integrity check.")
        }

        let handoff = try FilmAnimaticHandoff.load(from: resolvedManifest)
        guard handoff.source.projectId == response.projectId,
              handoff.source.projectId == workspace.project.projectId,
              handoff.shots.count == response.shots,
              handoff.assets.count == response.assets else {
            throw FilmStudioServiceError.invalidResponse("The Animatic handoff does not match the export receipt or loaded film project.")
        }

        let declaredRun = try handoff.resolveRunManifest(relativeTo: resolvedManifest)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let requestedRun = workspace.runManifest.standardizedFileURL.resolvingSymlinksInPath()
        guard declaredRun == requestedRun else {
            throw FilmStudioServiceError.invalidResponse("The Animatic handoff belongs to a different film run.")
        }
        let declaredRoot = try handoff.projectRootURL(relativeTo: resolvedManifest)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard declaredRoot == projectRoot else {
            throw FilmStudioServiceError.invalidResponse("The Animatic handoff declares a different film workspace.")
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
            try Task.checkCancellation()
            let url = try handoff.resolveAsset(asset, relativeTo: handoffURL)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw FilmStudioServiceError.invalidResponse("Missing handoff asset: \(asset.relativePath)")
            }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.intValue == asset.bytes else {
                throw FilmStudioServiceError.invalidResponse("Handoff asset size changed after export: \(asset.relativePath)")
            }
            let actualHash = try sha256(of: url)
            guard actualHash == asset.sha256 else {
                throw FilmStudioServiceError.invalidResponse("Handoff asset failed its SHA-256 integrity check: \(asset.relativePath)")
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

    @concurrent
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else { break }
            hasher.update(data: data)
        }
        let digest = hasher.finalize()
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}
