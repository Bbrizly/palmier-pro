import FilmStudioCore
import Foundation
import Testing

@Suite("Film Studio GRACE contracts")
struct FilmStudioContractTests {
    @Test
    func loadsNestedBriefProductionPlanAndPlayableCut() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkspaceDirectories(root)

        let runManifest = root.appending(path: "run.json")
        let projectManifest = root.appending(path: "film-project.json")
        try Data(runManifestJSON(root: root, runManifest: runManifest, projectManifest: projectManifest).utf8)
            .write(to: runManifest)
        try Data(projectJSON.utf8).write(to: projectManifest)
        try Data(productionPlanJSON.utf8).write(to: root.appending(path: "production-plan.json"))
        try Data(treatmentJSON.utf8).write(to: root.appending(path: "treatment.json"))
        try Data([0x00]).write(to: root.appending(path: "cuts/rough-cut.mp4"))

        let snapshot = try FilmProjectLoader.load(runManifest: runManifest)

        #expect(snapshot.root == root.standardizedFileURL.resolvingSymlinksInPath())
        #expect(snapshot.runManifest == runManifest.standardizedFileURL.resolvingSymlinksInPath())
        #expect(snapshot.project.projectId == "contract-test")
        #expect(snapshot.project.title == "Contract Test")
        #expect(snapshot.project.idea == "Test the GRACE contract adapter.")
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
    func loadsWorkspaceWhenRunManifestLivesOutsideProjectRoot() throws {
        let container = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appending(path: "film", directoryHint: .isDirectory)
        let manifests = container.appending(path: "manifests", directoryHint: .isDirectory)
        try makeWorkspaceDirectories(root)
        try FileManager.default.createDirectory(at: manifests, withIntermediateDirectories: true)

        let runManifest = manifests.appending(path: "custom-film-run.json")
        let projectManifest = root.appending(path: "film-project.json")
        try Data(runManifestJSON(root: root, runManifest: runManifest, projectManifest: projectManifest).utf8)
            .write(to: runManifest)
        try Data(projectJSON.utf8).write(to: projectManifest)

        let snapshot = try FilmProjectLoader.load(runManifest: runManifest)

        #expect(snapshot.root == root.standardizedFileURL.resolvingSymlinksInPath())
        #expect(snapshot.runManifest == runManifest.standardizedFileURL.resolvingSymlinksInPath())
        #expect(snapshot.project.projectId == "contract-test")
    }

    @Test
    func rejectsUnsupportedRunContract() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkspaceDirectories(root)

        let runManifest = root.appending(path: "run.json")
        let projectManifest = root.appending(path: "film-project.json")
        let invalidRun = runManifestJSON(root: root, runManifest: runManifest, projectManifest: projectManifest)
            .replacingOccurrences(of: "mere.run/plugin-run.v1", with: "mere.run/plugin-run.v999")
        try Data(invalidRun.utf8).write(to: runManifest)
        try Data(projectJSON.utf8).write(to: projectManifest)

        #expect(throws: FilmProjectError.unsupportedRunContract("mere.run/plugin-run.v999")) {
            _ = try FilmProjectLoader.load(runManifest: runManifest)
        }
    }

    @Test
    func rejectsUnsupportedProjectContract() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeWorkspaceDirectories(root)

        let runManifest = root.appending(path: "run.json")
        let projectManifest = root.appending(path: "film-project.json")
        try Data(runManifestJSON(root: root, runManifest: runManifest, projectManifest: projectManifest).utf8)
            .write(to: runManifest)
        try Data(projectJSON.replacingOccurrences(
            of: "mere.run/film-project.v1",
            with: "mere.run/film-project.v999"
        ).utf8).write(to: projectManifest)

        #expect(throws: FilmProjectError.unsupportedContract("mere.run/film-project.v999")) {
            _ = try FilmProjectLoader.load(runManifest: runManifest)
        }
    }

    @Test
    func rejectsProjectManifestOutsideDeclaredWorkspace() throws {
        let container = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: container) }
        let root = container.appending(path: "film", directoryHint: .isDirectory)
        let other = container.appending(path: "other", directoryHint: .isDirectory)
        try makeWorkspaceDirectories(root)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        let runManifest = root.appending(path: "run.json")
        let wrongProject = other.appending(path: "film-project.json")
        try Data(runManifestJSON(root: root, runManifest: runManifest, projectManifest: wrongProject).utf8)
            .write(to: runManifest)
        try Data(projectJSON.utf8).write(to: wrongProject)

        #expect(throws: FilmProjectError.invalidRunManifest(
            "local.projectManifest must resolve to the workspace film-project.json."
        )) {
            _ = try FilmProjectLoader.load(runManifest: runManifest)
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "film-studio-contract-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeWorkspaceDirectories(_ root: URL) throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: "cuts", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private func runManifestJSON(root: URL, runManifest: URL, projectManifest: URL) -> String {
        """
        {
          "contractVersion": "mere.run/plugin-run.v1",
          "runId": "contract-test-run",
          "plugin": {"name": "mere-film-tools", "version": "0.1.0"},
          "local": {
            "outputDirectory": "\(root.path)",
            "runManifest": "\(runManifest.path)",
            "projectManifest": "\(projectManifest.path)"
          }
        }
        """
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
              "resolvedFields": 6,
              "totalFields": 6
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
            "commands": {
              "pi": "pi",
              "mereRun": "mere.run",
              "ffmpeg": "ffmpeg",
              "ffprobe": "ffprobe"
            },
            "models": {
              "imageMaster": "image-master",
              "imageShot": "image-shot",
              "video": "video-model",
              "visionInspector": "auto-qwen3-vl-2b",
              "speechAsr": "speech-asr",
              "speechTts": "speech-tts",
              "sfx": "sfx-model",
              "music": "music-model"
            },
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
