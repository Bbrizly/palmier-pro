import FilmStudioCore
import Foundation
import Testing

@Suite("Film Studio GRACE contracts")
struct FilmStudioContractTests {
    @Test
    func loadsNestedBriefProductionPlanAndPlayableCut() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-studio-contract-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: root.appending(path: "cuts", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )

        let runManifest = root.appending(path: "run.json")
        try Data("{}".utf8).write(to: runManifest)
        try Data(projectJSON.utf8).write(to: root.appending(path: "film-project.json"))
        try Data(productionPlanJSON.utf8).write(to: root.appending(path: "production-plan.json"))
        try Data(treatmentJSON.utf8).write(to: root.appending(path: "treatment.json"))
        try Data([0x00]).write(to: root.appending(path: "cuts/rough-cut.mp4"))

        let snapshot = try FilmProjectLoader.load(runManifest: runManifest)

        #expect(snapshot.project.title == "Contract Test")
        #expect(snapshot.project.brief.audience == "Editors")
        #expect(snapshot.project.brief.genre == "Drama")
        #expect(snapshot.project.brief.tone == "Grounded")
        #expect(snapshot.project.brief.rating == "PG")
        #expect(snapshot.project.brief.usage == "commercial")
        #expect(snapshot.project.brief.references == ["Reference A"])
        #expect(snapshot.productionPlan?.shots.first?.id == "opening-shot")
        #expect(snapshot.productionPlan?.shots.first?.take == 2)
        #expect(snapshot.treatment?.logline == "A concise logline.")
        #expect(snapshot.playableCutURL?.lastPathComponent == "rough-cut.mp4")
    }

    @Test
    func rejectsUnsupportedProjectContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "film-studio-contract-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let runManifest = root.appending(path: "run.json")
        try Data("{}".utf8).write(to: runManifest)
        try Data(projectJSON.replacingOccurrences(
            of: "mere.run/film-project.v1",
            with: "mere.run/film-project.v999"
        ).utf8).write(to: root.appending(path: "film-project.json"))

        #expect(throws: FilmProjectError.unsupportedContract("mere.run/film-project.v999")) {
            _ = try FilmProjectLoader.load(runManifest: runManifest)
        }
    }

    private var projectJSON: String {
        """
        {
          "contractVersion": "mere.run/film-project.v1",
          "projectId": "contract-test",
          "title": "Contract Test",
          "idea": "Test the GRACE contract adapter.",
          "createdAt": "2026-08-25T12:00:00Z",
          "updatedAt": "2026-08-25T12:01:00Z",
          "status": "awaiting-approval",
          "phase": "production",
          "brief": {
            "contractVersion": "mere.run/film-brief.v1",
            "title": "Contract Test",
            "idea": "Test the GRACE contract adapter.",
            "target": {
              "durationSeconds": 45,
              "width": 1920,
              "height": 1080,
              "fps": 24,
              "aspectRatio": "16:9",
              "audience": "Editors",
              "rating": "PG",
              "language": "en",
              "platform": "web",
              "usage": "commercial"
            },
            "creative": {
              "genre": "Drama",
              "tone": "Grounded",
              "mustHaves": [],
              "exclusions": [],
              "references": ["Reference A"]
            },
            "openQuestions": [],
            "completeness": {
              "readyForGreenlight": true,
              "resolvedFields": 5,
              "totalFields": 5
            }
          },
          "approvals": {
            "brief": {"status": "approved"},
            "treatment": {"status": "approved"},
            "production": {"status": "pending"},
            "picture-lock": {"status": "blocked"},
            "delivery": {"status": "blocked"}
          },
          "departments": [],
          "shots": [
            {"id": "opening-shot", "status": "succeeded", "take": 2}
          ],
          "reviewRequests": [],
          "jobs": [
            {"id": "opening-shot-clip", "kind": "clip", "status": "succeeded"}
          ],
          "production": {
            "mode": "draft",
            "takesPerShot": 2,
            "generateScore": true,
            "inspectGeneratedMedia": true,
            "maxParallelAgents": 1,
            "piTimeoutSeconds": 600,
            "mediaTimeoutSeconds": 1200,
            "commands": {},
            "models": {},
            "resourcePolicy": {}
          },
          "artifacts": [
            {"kind": "rough-cut", "path": "cuts/rough-cut.mp4"}
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
          },
          "issues": [],
          "history": []
        }
        """
    }

    private var productionPlanJSON: String {
        """
        {
          "contractVersion": "mere.run/film-production-plan.v1",
          "projectId": "contract-test",
          "title": "Contract Test",
          "createdAt": "2026-08-25T12:00:00Z",
          "target": {},
          "scorePrompt": "Minimal score.",
          "cast": [],
          "locations": [],
          "shots": [
            {
              "id": "opening-shot",
              "purpose": "Establish the scene",
              "framePrompt": "Wide establishing frame",
              "prompt": "A deliberate establishing shot",
              "durationSeconds": 4.5,
              "seed": 4,
              "characters": [],
              "location": "studio",
              "dialogue": [],
              "soundEffects": [],
              "transition": "cut",
              "status": "succeeded",
              "take": 2
            }
          ],
          "plannedDurationSeconds": 4.5
        }
        """
    }

    private var treatmentJSON: String {
        """
        {
          "title": "Contract Test",
          "logline": "A concise logline.",
          "synopsis": "A short synopsis.",
          "theme": "Precision",
          "beats": ["Setup", "Turn", "Resolution"],
          "visualLanguage": "Naturalistic",
          "soundLanguage": "Restrained"
        }
        """
    }
}
