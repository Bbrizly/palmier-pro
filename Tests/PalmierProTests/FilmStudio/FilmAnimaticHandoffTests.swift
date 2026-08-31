import FilmStudioCore
import Foundation
import Testing

@Suite("Film Studio animatic handoff")
struct FilmAnimaticHandoffTests {
    @Test
    func loadsAndOrdersCurrentShotTakes() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let handoffURL = root.appending(path: "handoff.json")
        try Data(validHandoffJSON.utf8).write(to: handoffURL)

        let handoff = try FilmAnimaticHandoff.load(from: handoffURL)

        #expect(handoff.contractVersion == "mere.run/film-animatic-handoff.v1")
        #expect(handoff.timeline.frameRate == 24)
        #expect(handoff.orderedShots.map(\.shotId) == ["SHOT-001", "SHOT-002"])
        #expect(handoff.orderedShots.map(\.take) == [2, 1])
        #expect(handoff.orderedShots[0].timeline.trimInSeconds == 0.25)
        #expect(handoff.resolve(handoff.orderedShots[0].clipPath, relativeTo: root.appending(path: "run.json"))
            == root.appending(path: "shots/SHOT-001/takes/take-002/clip.mp4").standardizedFileURL)
    }

    @Test
    func rejectsUnsupportedHandoffContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let handoffURL = root.appending(path: "handoff.json")
        try Data(validHandoffJSON.replacingOccurrences(
            of: "mere.run/film-animatic-handoff.v1",
            with: "mere.run/film-animatic-handoff.v999"
        ).utf8).write(to: handoffURL)

        #expect(throws: FilmAnimaticHandoff.ValidationError.unsupportedContract("mere.run/film-animatic-handoff.v999")) {
            _ = try FilmAnimaticHandoff.load(from: handoffURL)
        }
    }

    @Test
    func rejectsPathTraversal() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let handoffURL = root.appending(path: "handoff.json")
        try Data(validHandoffJSON.replacingOccurrences(
            of: "shots/SHOT-001/takes/take-002/clip.mp4",
            with: "../outside.mp4"
        ).utf8).write(to: handoffURL)

        #expect(throws: FilmAnimaticHandoff.ValidationError.invalidPath("../outside.mp4")) {
            _ = try FilmAnimaticHandoff.load(from: handoffURL)
        }
    }

    private var validHandoffJSON: String {
        """
        {
          "contractVersion": "mere.run/film-animatic-handoff.v1",
          "project": {
            "title": "Contract Test",
            "runManifest": "run.json",
            "filmProject": "film-project.json"
          },
          "timeline": {
            "frameRate": 24,
            "aspectRatio": "16:9",
            "resolution": {"width": 1920, "height": 1080},
            "tracks": {"picture": "V1", "dialogue": "A1", "music": "A2", "effects": "A3"}
          },
          "media": {
            "dialogueBed": "audio/dialogue.wav",
            "musicBed": "audio/music.wav",
            "effectsBed": null,
            "roughCut": "cuts/rough-cut.mp4",
            "deliveryMaster": null
          },
          "shots": [
            {
              "shotId": "SHOT-002",
              "order": 20,
              "slug": "Second",
              "clipAssetId": "clip-2",
              "clipPath": "shots/SHOT-002/takes/take-001/clip.mp4",
              "take": 1,
              "source": {
                "kind": "generated",
                "provider": "demo",
                "model": "video-model",
                "strategy": "text-to-video",
                "inputArtifact": null,
                "referenceArtifacts": [],
                "parentClipAssetId": null,
                "integrationId": "palmier-pro"
              },
              "timeline": {"startSeconds": 3, "durationSeconds": 2, "trimInSeconds": 0, "trimOutSeconds": 0},
              "audio": {"dialogue": true, "music": true, "effects": false, "dialogueBed": "audio/dialogue.wav", "musicBed": "audio/music.wav", "effectsBed": null},
              "evidence": {"clip": "evidence/SHOT-002.json", "cut": null}
            },
            {
              "shotId": "SHOT-001",
              "order": 10,
              "slug": "First",
              "clipAssetId": "clip-1",
              "clipPath": "shots/SHOT-001/takes/take-002/clip.mp4",
              "take": 2,
              "source": {
                "kind": "generated",
                "referenceArtifacts": []
              },
              "timeline": {"startSeconds": 0, "durationSeconds": 3, "trimInSeconds": 0.25, "trimOutSeconds": 0.5},
              "audio": {"dialogue": true, "music": true, "effects": false, "dialogueBed": "audio/dialogue.wav", "musicBed": "audio/music.wav", "effectsBed": null},
              "evidence": {"clip": "evidence/SHOT-001.json", "cut": "evidence/cut.json"}
            }
          ]
        }
        """
    }
}