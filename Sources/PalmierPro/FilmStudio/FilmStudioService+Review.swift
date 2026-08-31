import FilmStudioCore
import Foundation

struct FilmStudioReviewReroll: Sendable, Equatable {
    let shotID: String
    let note: String
}

struct FilmStudioCreativeReview: Decodable, Sendable, Equatable {
    let decision: String
    let issues: [Issue]
    let rerolls: [Reroll]
    let strengths: [String]
    let deliveryNotes: [String]

    struct Issue: Decodable, Sendable, Equatable, Identifiable {
        var id: String { "\(code):\(shotId ?? ""):\(message)" }

        let code: String
        let severity: String
        let message: String
        let shotId: String?
    }

    struct Reroll: Decodable, Sendable, Equatable, Identifiable {
        var id: String { "\(shotId):\(reason):\(direction)" }

        let shotId: String
        let reason: String
        let direction: String

        var note: String {
            [reason, direction]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case decision
        case issues
        case rerolls
        case strengths
        case deliveryNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        decision = try container.decode(String.self, forKey: .decision)
        issues = try container.decodeIfPresent([Issue].self, forKey: .issues) ?? []
        rerolls = try container.decodeIfPresent([Reroll].self, forKey: .rerolls) ?? []
        strengths = try container.decodeIfPresent([String].self, forKey: .strengths) ?? []
        deliveryNotes = try container.decodeIfPresent([String].self, forKey: .deliveryNotes) ?? []
    }

    func validate(knownShotIDs: Set<String>) throws {
        guard decision == "pass" || decision == "revise" else {
            throw FilmStudioServiceError.invalidResponse("Independent review decision must be pass or revise.")
        }
        for issue in issues {
            guard !issue.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !issue.severity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !issue.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FilmStudioServiceError.invalidResponse("Independent review contains an incomplete issue.")
            }
            if let shotID = issue.shotId, !knownShotIDs.contains(shotID) {
                throw FilmStudioServiceError.invalidResponse("Independent review references unknown shot \(shotID).")
            }
        }
        for reroll in rerolls {
            guard knownShotIDs.contains(reroll.shotId), !reroll.note.isEmpty else {
                throw FilmStudioServiceError.invalidResponse("Independent review contains an invalid reroll request.")
            }
        }
    }
}

extension FilmStudioService {
    @concurrent
    static func loadCreativeReview(runManifest: URL) async throws -> FilmStudioCreativeReview? {
        try Task.checkCancellation()
        let workspace = try FilmProjectLoader.load(runManifest: runManifest)
        let url = workspace.root.appending(path: "reviews/creative-review.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let review = try JSONDecoder().decode(FilmStudioCreativeReview.self, from: Data(contentsOf: url))
            let knownShotIDs = Set(workspace.productionPlan?.shots.map(\.id) ?? workspace.project.shots.map(\.id))
            try review.validate(knownShotIDs: knownShotIDs)
            return review
        } catch let error as FilmStudioServiceError {
            throw error
        } catch {
            throw FilmStudioServiceError.invalidResponse(
                "Could not read the independent review: \(error.localizedDescription)"
            )
        }
    }

    @concurrent
    static func recordReviewDecision(
        runManifest: URL,
        decision: String,
        reviewer: String,
        note: String,
        rerolls: [FilmStudioReviewReroll],
        filmToolPath: String
    ) async throws {
        guard decision == "approve" || decision == "revise" else {
            throw FilmStudioServiceError.invalidResponse("Review decision must be approve or revise.")
        }
        if decision == "approve", !rerolls.isEmpty {
            throw FilmStudioServiceError.invalidResponse("An approved cut cannot include reroll requests.")
        }
        if decision == "revise", rerolls.isEmpty {
            throw FilmStudioServiceError.invalidResponse(
                "Choose at least one shot to revise so the workflow has an actionable next step."
            )
        }

        let workspace = try FilmProjectLoader.load(runManifest: runManifest)
        let knownShotIDs = Set(workspace.productionPlan?.shots.map(\.id) ?? workspace.project.shots.map(\.id))
        var seenShotIDs = Set<String>()
        guard rerolls.allSatisfy({ reroll in
            let shotID = reroll.shotID.trimmingCharacters(in: .whitespacesAndNewlines)
            let revision = reroll.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return !shotID.isEmpty
                && !revision.isEmpty
                && knownShotIDs.contains(shotID)
                && seenShotIDs.insert(shotID).inserted
        }) else {
            throw FilmStudioServiceError.invalidResponse(
                "Every reroll request must target one unique current shot and include a specific revision note."
            )
        }

        let filmTool = try await FilmStudioRuntimeCompatibility.requireFilmTools(filmToolPath)
        var arguments = [
            "review-decision", workspace.runManifest.path,
            "--decision", decision,
            "--reviewer", reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "macOS user" : reviewer,
            "--note", note,
        ]
        for reroll in rerolls {
            arguments.append(contentsOf: [
                "--reroll",
                "\(reroll.shotID.trimmingCharacters(in: .whitespacesAndNewlines)):\(reroll.note.trimmingCharacters(in: .whitespacesAndNewlines))",
            ])
        }
        _ = try await FilmToolClient(executable: filmTool.path).run(
            arguments,
            environment: processEnvironment()
        )
    }
}
