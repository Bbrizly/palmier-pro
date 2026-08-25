import FilmStudioCore
import Foundation

struct FilmStudioReviewReroll: Sendable, Equatable {
    let shotID: String
    let note: String
}

extension FilmStudioService {
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
            throw FilmStudioServiceError.invalidResponse("Choose at least one shot to revise so the workflow has an actionable next step.")
        }
        guard rerolls.allSatisfy({ !$0.shotID.isEmpty && !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw FilmStudioServiceError.invalidResponse("Every reroll request needs a shot and a specific revision note.")
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
