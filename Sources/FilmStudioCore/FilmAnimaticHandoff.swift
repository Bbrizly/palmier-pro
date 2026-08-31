import Foundation

public struct FilmAnimaticHandoff: Codable, Sendable, Equatable {
    public let contractVersion: String
    public let project: Project
    public let timeline: Timeline
    public let media: Media
    public let shots: [Shot]

    public struct Project: Codable, Sendable, Equatable {
        public let title: String
        public let runManifest: String
        public let filmProject: String
    }

    public struct Timeline: Codable, Sendable, Equatable {
        public let frameRate: Double
        public let aspectRatio: String
        public let resolution: Resolution
        public let tracks: Tracks
    }

    public struct Resolution: Codable, Sendable, Equatable {
        public let width: Int
        public let height: Int
    }

    public struct Tracks: Codable, Sendable, Equatable {
        public let picture: String
        public let dialogue: String
        public let music: String
        public let effects: String
    }

    public struct Media: Codable, Sendable, Equatable {
        public let dialogueBed: String?
        public let musicBed: String?
        public let effectsBed: String?
        public let roughCut: String?
        public let deliveryMaster: String?
    }

    public struct Shot: Codable, Sendable, Equatable, Identifiable {
        public var id: String { shotId }

        public let shotId: String
        public let order: Int
        public let slug: String
        public let clipAssetId: String
        public let clipPath: String
        public let take: Int
        public let source: Source
        public let timeline: ShotTimeline
        public let audio: Audio
        public let evidence: Evidence
    }

    public struct Source: Codable, Sendable, Equatable {
        public let kind: String
        public let provider: String?
        public let model: String?
        public let strategy: String?
        public let inputArtifact: String?
        public let referenceArtifacts: [String]
        public let parentClipAssetId: String?
        public let integrationId: String?

        public init(
            kind: String,
            provider: String? = nil,
            model: String? = nil,
            strategy: String? = nil,
            inputArtifact: String? = nil,
            referenceArtifacts: [String] = [],
            parentClipAssetId: String? = nil,
            integrationId: String? = nil
        ) {
            self.kind = kind
            self.provider = provider
            self.model = model
            self.strategy = strategy
            self.inputArtifact = inputArtifact
            self.referenceArtifacts = referenceArtifacts
            self.parentClipAssetId = parentClipAssetId
            self.integrationId = integrationId
        }

        private enum CodingKeys: String, CodingKey {
            case kind, provider, model, strategy, inputArtifact, referenceArtifacts, parentClipAssetId, integrationId
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            provider = try container.decodeIfPresent(String.self, forKey: .provider)
            model = try container.decodeIfPresent(String.self, forKey: .model)
            strategy = try container.decodeIfPresent(String.self, forKey: .strategy)
            inputArtifact = try container.decodeIfPresent(String.self, forKey: .inputArtifact)
            referenceArtifacts = try container.decodeIfPresent([String].self, forKey: .referenceArtifacts) ?? []
            parentClipAssetId = try container.decodeIfPresent(String.self, forKey: .parentClipAssetId)
            integrationId = try container.decodeIfPresent(String.self, forKey: .integrationId)
        }
    }

    public struct ShotTimeline: Codable, Sendable, Equatable {
        public let startSeconds: Double
        public let durationSeconds: Double
        public let trimInSeconds: Double
        public let trimOutSeconds: Double
    }

    public struct Audio: Codable, Sendable, Equatable {
        public let dialogue: Bool
        public let music: Bool
        public let effects: Bool
        public let dialogueBed: String?
        public let musicBed: String?
        public let effectsBed: String?
    }

    public struct Evidence: Codable, Sendable, Equatable {
        public let clip: String?
        public let cut: String?
    }

    public enum ValidationError: LocalizedError, Equatable {
        case unsupportedContract(String)
        case invalidFrameRate(Double)
        case invalidResolution(Int, Int)
        case duplicateShotID(String)
        case invalidShotTiming(String)
        case invalidPath(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedContract(let value):
                "Unsupported film handoff contract: \(value)"
            case .invalidFrameRate(let value):
                "Invalid film handoff frame rate: \(value)"
            case .invalidResolution(let width, let height):
                "Invalid film handoff resolution: \(width)x\(height)"
            case .duplicateShotID(let id):
                "Film handoff contains duplicate shot id: \(id)"
            case .invalidShotTiming(let id):
                "Film handoff contains invalid timing for shot: \(id)"
            case .invalidPath(let path):
                "Film handoff contains an invalid relative path: \(path)"
            }
        }
    }

    public static func load(from url: URL) throws -> FilmAnimaticHandoff {
        let handoff = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try handoff.validate()
        return handoff
    }

    public func validate() throws {
        guard contractVersion == "mere.run/film-animatic-handoff.v1" else {
            throw ValidationError.unsupportedContract(contractVersion)
        }
        guard timeline.frameRate.isFinite, timeline.frameRate > 0 else {
            throw ValidationError.invalidFrameRate(timeline.frameRate)
        }
        guard timeline.resolution.width > 0, timeline.resolution.height > 0 else {
            throw ValidationError.invalidResolution(timeline.resolution.width, timeline.resolution.height)
        }

        let topLevelPaths = [
            project.runManifest,
            project.filmProject,
            media.dialogueBed,
            media.musicBed,
            media.effectsBed,
            media.roughCut,
            media.deliveryMaster,
        ].compactMap { $0 }
        for path in topLevelPaths where !Self.isSafeRelativePath(path) {
            throw ValidationError.invalidPath(path)
        }

        var ids = Set<String>()
        for shot in shots {
            guard ids.insert(shot.shotId).inserted else {
                throw ValidationError.duplicateShotID(shot.shotId)
            }
            guard shot.timeline.startSeconds.isFinite,
                  shot.timeline.startSeconds >= 0,
                  shot.timeline.durationSeconds.isFinite,
                  shot.timeline.durationSeconds > 0,
                  shot.timeline.trimInSeconds.isFinite,
                  shot.timeline.trimInSeconds >= 0,
                  shot.timeline.trimOutSeconds.isFinite,
                  shot.timeline.trimOutSeconds >= 0 else {
                throw ValidationError.invalidShotTiming(shot.shotId)
            }
            guard Self.isSafeRelativePath(shot.clipPath) else {
                throw ValidationError.invalidPath(shot.clipPath)
            }
            for path in [shot.audio.dialogueBed, shot.audio.musicBed, shot.audio.effectsBed, shot.evidence.clip, shot.evidence.cut].compactMap({ $0 }) where !Self.isSafeRelativePath(path) {
                throw ValidationError.invalidPath(path)
            }
        }
    }

    public var orderedShots: [Shot] {
        shots.sorted {
            if $0.timeline.startSeconds == $1.timeline.startSeconds {
                if $0.order == $1.order { return $0.shotId < $1.shotId }
                return $0.order < $1.order
            }
            return $0.timeline.startSeconds < $1.timeline.startSeconds
        }
    }

    public func resolve(_ relativePath: String, relativeTo runManifest: URL) -> URL {
        runManifest.deletingLastPathComponent()
            .appending(path: relativePath)
            .standardizedFileURL
    }

    private static func isSafeRelativePath(_ rawPath: String) -> Bool {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = NSString(string: path).pathComponents
        return !components.contains("..") && !components.contains(".")
    }
}