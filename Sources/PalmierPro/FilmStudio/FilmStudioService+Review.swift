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
}

extension FilmStudioService {
    @concurrent
    static func loadCreativeReview(runManifest: URL) async throws -> FilmStudioCreativeReview? {
        let root = runManifest.lastPathComponent == "run.json"
            ? runManifest.deletingLastPathComponent()
            : runManifest
        let url = root.appending(path: "reviews/creative-review.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            return try JSONDecoder().decode(FilmStudioCreativeReview.self, from: Data(contentsOf: url))
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
        guard rerolls.allSatisfy({
            !$0.shotID.isEmpty
                && !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw FilmStudioServiceError.invalidResponse(
                "Every reroll request needs a shot and a specific revision note."
            )
        }

        var arguments = [
            "review-decision", runManifest.path,
            "--decision", decision,
            "--reviewer", reviewer,
            "--note", note,
        ]
        for reroll in rerolls {
            arguments.append(contentsOf: ["--reroll", "\(reroll.shotID):\(reroll.note)"])
        }
        _ = try await FilmToolClient(executable: filmToolPath).run(
            arguments,
            environment: processEnvironment()
        )
    }
}
