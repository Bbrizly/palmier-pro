import FilmStudioCore
import Foundation
import Testing

@Suite("Film Studio animatic handoff")
struct FilmAnimaticHandoffTests {
    @Test
    func loadsCurrentContractAndResolvesAssets() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let exportDirectory = root.appending(path: "exports/animatic", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let handoffURL = exportDirectory.appending(path: "film-animatic-handoff.json")
        try Data(validHandoffJSON.utf8).write(to: handoffURL)

        let handoff = try FilmAnimaticHandoff.load(from: handoffURL)

        #expect(handoff.contractVersion == "mere.run/film-animatic-handoff.v1")
        #expect(handoff.project.fps == 24)
        #expect(handoff.orderedShots.map(\.id) == ["SHOT-001", "SHOT-002"])
        #expect(handoff.orderedShots.map(\.take) == [2, 1])
        #expect(handoff.orderedShots[0].durationSeconds == 3)
        #expect(handoff.referenceAsset?.kind == "rough-cut")

        let clip = try #require(handoff.asset(id: "film_asset_clip_1"))
        #expect(try handoff.resolveAsset(clip, relativeTo: handoffURL)
            == root.appending(path: "clips/SHOT-001.mp4").standardizedFileURL)
        #expect(try handoff.resolveRunManifest(relativeTo: handoffURL)
            == root.appending(path: "run.json").standardizedFileURL)
    }

    @Test
    func rejectsUnsupportedHandoffContract() throws {
        let url = try writeHandoff(validHandoffJSON.replacingOccurrences(
            of: "mere.run/film-animatic-handoff.v1",
            with: "mere.run/film-animatic-handoff.v999"
        ))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }

        #expect(throws: FilmAnimaticHandoff.ValidationError.unsupportedContract("mere.run/film-animatic-handoff.v999")) {
            _ = try FilmAnimaticHandoff.load(from: url)
        }
    }

    @Test
    func rejectsAssetPathTraversal() throws {
        let url = try writeHandoff(validHandoffJSON.replacingOccurrences(
            of: "clips/SHOT-001.mp4",
            with: "../outside.mp4"
        ))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }

        #expect(throws: FilmAnimaticHandoff.ValidationError.invalidPath("../outside.mp4")) {
            _ = try FilmAnimaticHandoff.load(from: url)
        }
    }

    @Test
    func rejectsUnknownShotAssetReference() throws {
        let url = try writeHandoff(validHandoffJSON.replacingOccurrences(
            of: "\"clipAssetId\": \"film_asset_clip_1\"",
            with: "\"clipAssetId\": \"missing_asset\""
        ))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }

        #expect(throws: FilmAnimaticHandoff.ValidationError.missingAssetReference("missing_asset")) {
            _ = try FilmAnimaticHandoff.load(from: url)
        }
    }

    private func writeHandoff(_ json: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        let directory = root.appending(path: "exports/animatic", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "film-animatic-handoff.json")
        try Data(json.utf8).write(to: url)
        return url
    }

    private var validHandoffJSON: String {
        """
        {
          "contractVersion": "mere.run/film-animatic-handoff.v1",
          "exportedAt": "2026-08-31T15:00:00+00:00",
          "source": {
            "projectId": "contract-test",
            "projectRoot": "../..",
            "runManifest": "run.json",
            "projectContractVersion": "mere.run/film-project.v1",
            "updatedAt": "2026-08-31T14:59:00+00:00"
          },
          "project": {
            "title": "Contract Test",
            "idea": "A test film.",
            "logline": "Two shots prove a contract.",
            "synopsis": null,
            "theme": null,
            "durationMilliseconds": 5000,
            "fps": 24,
            "aspectRatio": "16:9",
            "width": 1920,
            "height": 1080
          },
          "cast": [
            {
              "id": "keeper",
              "name": "Keeper",
              "visual": "Weathered keeper",
              "wardrobe": "Work coat",
              "voice": "Quiet",
              "seed": 42
            }
          ],
          "locations": [
            {
              "id": "lighthouse",
              "name": "Lighthouse",
              "visual": "Storm-dark lamp room",
              "ambience": "Wind",
              "seed": 99
            }
          ],
          "shots": [
            {
              "id": "SHOT-002",
              "order": 1,
              "purpose": "Resolve the beat",
              "prompt": "Second shot",
              "framePrompt": "Second frame",
              "timelineStartMilliseconds": 3000,
              "durationMilliseconds": 2000,
              "characterIds": ["keeper"],
              "locationId": "lighthouse",
              "transition": "fade",
              "take": 1,
              "seed": 202,
              "keyframeAssetId": null,
              "clipAssetId": "film_asset_clip_2",
              "dialogue": [
                {"speaker": "keeper", "text": "I hear you.", "startSeconds": 0.5, "delivery": "quiet"}
              ],
              "soundEffects": []
            },
            {
              "id": "SHOT-001",
              "order": 0,
              "purpose": "Open the beat",
              "prompt": "First shot",
              "framePrompt": "First frame",
              "timelineStartMilliseconds": 0,
              "durationMilliseconds": 3000,
              "characterIds": ["keeper"],
              "locationId": "lighthouse",
              "transition": "cut",
              "take": 2,
              "seed": 101,
              "keyframeAssetId": null,
              "clipAssetId": "film_asset_clip_1",
              "dialogue": [],
              "soundEffects": [
                {"prompt": "relay click", "startSeconds": 0.7, "durationSeconds": 1.0, "levelDb": -9, "seed": 303}
              ]
            }
          ],
          "assets": [
            {
              "id": "film_asset_clip_1",
              "kind": "shot-clip",
              "relativePath": "clips/SHOT-001.mp4",
              "sha256": "sha256:0000000000000000000000000000000000000000000000000000000000000000",
              "bytes": 100,
              "contentType": "video/mp4",
              "source": "mere.run"
            },
            {
              "id": "film_asset_clip_2",
              "kind": "shot-clip",
              "relativePath": "clips/SHOT-002.mp4",
              "sha256": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
              "bytes": 100,
              "contentType": "video/mp4",
              "source": "mere.run"
            },
            {
              "id": "film_asset_rough",
              "kind": "rough-cut",
              "relativePath": "cuts/rough-cut.mp4",
              "sha256": "sha256:2222222222222222222222222222222222222222222222222222222222222222",
              "bytes": 200,
              "contentType": "video/mp4",
              "source": "mere-film-tools"
            }
          ],
          "proof": {
            "creation": true,
            "clips": true,
            "assembly": true,
            "dialogue": true,
            "sound": true,
            "captions": true,
            "inspection": true,
            "review": false,
            "humanReview": false,
            "delivery": false
          }
        }
        """
    }
}
