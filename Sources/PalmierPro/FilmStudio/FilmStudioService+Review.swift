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
        if decision == "revise", rerolls.isEmpty {
            throw FilmStudioServiceError.invalidResponse("Choose at least one shot to revise.")
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
            environment: reviewProcessEnvironment()
        )
    }

    private static func reviewProcessEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        var pathComponents = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let additions = [
            FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for addition in additions where !pathComponents.contains(addition) {
            pathComponents.append(addition)
        }
        environment["PATH"] = pathComponents.joined(separator: ":")
        return environment
    }
}
