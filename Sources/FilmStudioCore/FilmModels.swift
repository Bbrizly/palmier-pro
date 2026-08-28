import Foundation

public struct FilmWorkspaceSnapshot: Sendable, Equatable {
    public let root: URL
    public let runManifest: URL
    public let project: FilmProject
    public let productionPlan: FilmProductionPlan?
    public let treatment: FilmTreatment?

    public init(
        root: URL,
        runManifest: URL,
        project: FilmProject,
        productionPlan: FilmProductionPlan?,
        treatment: FilmTreatment?
    ) {
        self.root = root
        self.runManifest = runManifest
        self.project = project
        self.productionPlan = productionPlan
        self.treatment = treatment
    }

    public func artifactURL(_ artifact: FilmArtifact) -> URL {
        artifact.path.hasPrefix("/")
            ? URL(fileURLWithPath: artifact.path)
            : root.appending(path: artifact.path)
    }

    public func latestArtifact(kind: String) -> FilmArtifact? {
        project.artifacts.last { $0.kind == kind }
    }

    public var playableCutURL: URL? {
        for kind in ["delivery-master", "final-master", "rough-cut"] {
            guard let artifact = latestArtifact(kind: kind) else { continue }
            let url = artifactURL(artifact)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

public struct FilmProject: Decodable, Sendable, Equatable {
    public let contractVersion: String
    public let title: String
    public let updatedAt: String
    public let status: String
    public let phase: String
    public let brief: FilmBrief
    public let approvals: [String: FilmApproval]
    public let departments: [FilmDepartmentTask]
    public let shots: [FilmShotState]
    public let reviewRequests: [FilmReviewRequest]
    public let jobs: [FilmJob]
    public let production: FilmProductionConfiguration
    public let artifacts: [FilmArtifact]
    public let proof: FilmProof
    public let issues: [FilmIssue]
}

public struct FilmBrief: Decodable, Sendable, Equatable {
    public let audience: String?
    public let genre: String?
    public let tone: String?
    public let rating: String?
    public let usage: String?
    public let references: [String]
    public let openQuestions: [String]

    private struct Target: Decodable {
        let audience: String?
        let rating: String?
        let usage: String?
    }

    private struct Creative: Decodable {
        let genre: String?
        let tone: String?
        let references: [String]?
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case creative
        case audience
        case genre
        case tone
        case rating
        case usage
        case references
        case openQuestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let target = try container.decodeIfPresent(Target.self, forKey: .target)
        let creative = try container.decodeIfPresent(Creative.self, forKey: .creative)
        let flatAudience = try container.decodeIfPresent(String.self, forKey: .audience)
        let flatGenre = try container.decodeIfPresent(String.self, forKey: .genre)
        let flatTone = try container.decodeIfPresent(String.self, forKey: .tone)
        let flatRating = try container.decodeIfPresent(String.self, forKey: .rating)
        let flatUsage = try container.decodeIfPresent(String.self, forKey: .usage)
        let flatReferences = try container.decodeIfPresent([String].self, forKey: .references)

        audience = target?.audience ?? flatAudience
        genre = creative?.genre ?? flatGenre
        tone = creative?.tone ?? flatTone
        rating = target?.rating ?? flatRating
        usage = target?.usage ?? flatUsage
        references = creative?.references ?? flatReferences ?? []
        openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
    }
}

public struct FilmApproval: Decodable, Sendable, Equatable {
    public let status: String
}

public struct FilmDepartmentTask: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let role: String
    public let phase: String
    public let status: String
}

public struct FilmShotState: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let status: String?
    public let take: Int?
}

public struct FilmReviewRequest: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { "\(shotId):\(recordedAt)" }

    public let shotId: String
    public let note: String
    public let status: String
    public let recordedAt: String
    public let appliedAt: String?
    public let archivedTake: Int?
}

public struct FilmJob: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: String?
    public let status: String?
}

public struct FilmProductionConfiguration: Decodable, Sendable, Equatable {
    public let mode: String
    public let takesPerShot: Int
}

public struct FilmArtifact: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kind):\(path)" }

    public let kind: String
    public let path: String
}

public struct FilmProof: Decodable, Sendable, Equatable {
    public let creation: Bool
    public let clips: Bool
    public let assembly: Bool
    public let dialogue: Bool
    public let sound: Bool
    public let captions: Bool
    public let inspection: Bool
    public let review: Bool
    public let humanReview: Bool
    public let delivery: Bool

    public var completedCount: Int {
        [creation, clips, assembly, dialogue, sound, captions, inspection, review, humanReview, delivery]
            .filter { $0 }
            .count
    }
}

public struct FilmIssue: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { code }

    public let code: String
    public let message: String
    public let blocking: Bool
}

public struct FilmTreatment: Decodable, Sendable, Equatable {
    public let logline: String
    public let synopsis: String
    public let theme: String
    public let beats: [String]
    public let visualLanguage: String
    public let soundLanguage: String
}

public struct FilmProductionPlan: Decodable, Sendable, Equatable {
    public let shots: [FilmProductionShot]
}

public struct FilmProductionShot: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let purpose: String
    public let prompt: String
    public let durationSeconds: Double
    public let characters: [String]
    public let status: String
    public let take: Int
}
