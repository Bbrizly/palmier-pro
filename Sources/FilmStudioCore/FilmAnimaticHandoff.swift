import Foundation

public struct FilmAnimaticHandoff: Codable, Sendable, Equatable {
    public static let supportedContractVersion = "mere.run/film-animatic-handoff.v1"
    public static let supportedProjectContractVersion = "mere.run/film-project.v1"

    public let contractVersion: String
    public let exportedAt: String
    public let source: Source
    public let project: Project
    public let cast: [CastMember]
    public let locations: [Location]
    public let shots: [Shot]
    public let assets: [Asset]
    public let proof: Proof

    public struct Source: Codable, Sendable, Equatable {
        public let projectId: String
        public let projectRoot: String
        public let runManifest: String
        public let projectContractVersion: String
        public let updatedAt: String
    }

    public struct Project: Codable, Sendable, Equatable {
        public let title: String
        public let idea: String
        public let logline: String?
        public let synopsis: String?
        public let theme: String?
        public let durationMilliseconds: Int
        public let fps: Int
        public let aspectRatio: String
        public let width: Int?
        public let height: Int?
    }

    public struct CastMember: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let visual: String
        public let wardrobe: String
        public let voice: String
        public let seed: Int?
    }

    public struct Location: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let visual: String
        public let ambience: String
        public let seed: Int?
    }

    public struct Shot: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let order: Int
        public let purpose: String
        public let prompt: String
        public let framePrompt: String
        public let timelineStartMilliseconds: Int
        public let durationMilliseconds: Int
        public let characterIds: [String]
        public let locationId: String
        public let transition: String
        public let take: Int
        public let seed: Int
        public let keyframeAssetId: String?
        public let clipAssetId: String?
        public let dialogue: [Dialogue]
        public let soundEffects: [SoundEffect]

        public var timelineStartSeconds: Double {
            Double(timelineStartMilliseconds) / 1_000.0
        }

        public var durationSeconds: Double {
            Double(durationMilliseconds) / 1_000.0
        }
    }

    public struct Dialogue: Codable, Sendable, Equatable {
        public let speaker: String
        public let text: String
        public let startSeconds: Double
        public let delivery: String
    }

    public struct SoundEffect: Codable, Sendable, Equatable {
        public let prompt: String
        public let startSeconds: Double
        public let durationSeconds: Double
        public let levelDb: Double
        public let seed: Int
    }

    public struct Asset: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let kind: String
        public let relativePath: String
        public let sha256: String
        public let bytes: Int
        public let contentType: String
        public let source: String
    }

    public struct Proof: Codable, Sendable, Equatable {
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
    }

    public enum ValidationError: LocalizedError, Equatable {
        case unsupportedContract(String)
        case unsupportedProjectContract(String)
        case invalidProject(String)
        case duplicateCastID(String)
        case duplicateLocationID(String)
        case duplicateShotID(String)
        case duplicateShotOrder(Int)
        case duplicateAssetID(String)
        case duplicateAssetPath(String)
        case invalidShot(String)
        case invalidTimeline(String)
        case unknownCharacter(String)
        case unknownLocation(String)
        case missingAssetReference(String)
        case invalidAssetKind(String)
        case invalidPath(String)
        case invalidChecksum(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedContract(let value):
                "Unsupported film handoff contract: \(value)"
            case .unsupportedProjectContract(let value):
                "Unsupported film project contract in handoff: \(value)"
            case .invalidProject(let reason):
                "Invalid film handoff project: \(reason)"
            case .duplicateCastID(let id):
                "Film handoff contains duplicate cast id: \(id)"
            case .duplicateLocationID(let id):
                "Film handoff contains duplicate location id: \(id)"
            case .duplicateShotID(let id):
                "Film handoff contains duplicate shot id: \(id)"
            case .duplicateShotOrder(let order):
                "Film handoff contains duplicate shot order: \(order)"
            case .duplicateAssetID(let id):
                "Film handoff contains duplicate asset id: \(id)"
            case .duplicateAssetPath(let path):
                "Film handoff contains duplicate asset path: \(path)"
            case .invalidShot(let id):
                "Film handoff contains invalid timing or metadata for shot: \(id)"
            case .invalidTimeline(let reason):
                "Film handoff timeline is invalid: \(reason)"
            case .unknownCharacter(let id):
                "Film handoff references unknown cast id: \(id)"
            case .unknownLocation(let id):
                "Film handoff references unknown location id: \(id)"
            case .missingAssetReference(let id):
                "Film handoff references an unknown asset: \(id)"
            case .invalidAssetKind(let id):
                "Film handoff asset has the wrong kind for its reference: \(id)"
            case .invalidPath(let path):
                "Film handoff contains an invalid path: \(path)"
            case .invalidChecksum(let checksum):
                "Film handoff contains an invalid SHA-256 checksum: \(checksum)"
            }
        }
    }

    public static func load(from url: URL) throws -> FilmAnimaticHandoff {
        let handoff = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try handoff.validate()
        return handoff
    }

    public func validate() throws {
        guard contractVersion == Self.supportedContractVersion else {
            throw ValidationError.unsupportedContract(contractVersion)
        }
        guard source.projectContractVersion == Self.supportedProjectContractVersion else {
            throw ValidationError.unsupportedProjectContract(source.projectContractVersion)
        }
        guard !source.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidProject("source project id is required")
        }
        guard !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !project.idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              project.durationMilliseconds > 0,
              project.fps > 0,
              !project.aspectRatio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidProject("title, idea, duration, fps, and aspect ratio are required")
        }
        if let width = project.width, width <= 0 {
            throw ValidationError.invalidProject("width must be positive when present")
        }
        if let height = project.height, height <= 0 {
            throw ValidationError.invalidProject("height must be positive when present")
        }
        guard (project.width == nil) == (project.height == nil) else {
            throw ValidationError.invalidProject("width and height must either both be present or both be null")
        }
        guard !shots.isEmpty else {
            throw ValidationError.invalidProject("at least one shot is required")
        }
        guard Self.isSafeProjectRoot(source.projectRoot) else {
            throw ValidationError.invalidPath(source.projectRoot)
        }
        guard Self.isSafeRelativePath(source.runManifest) else {
            throw ValidationError.invalidPath(source.runManifest)
        }

        var castIDs = Set<String>()
        for member in cast {
            guard castIDs.insert(member.id).inserted else {
                throw ValidationError.duplicateCastID(member.id)
            }
            guard !member.id.isEmpty,
                  !member.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !member.visual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !member.wardrobe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !member.voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidProject("cast entries require id, name, visual, wardrobe, and voice")
            }
        }

        var locationIDs = Set<String>()
        for location in locations {
            guard locationIDs.insert(location.id).inserted else {
                throw ValidationError.duplicateLocationID(location.id)
            }
            guard !location.id.isEmpty,
                  !location.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !location.visual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !location.ambience.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidProject("location entries require id, name, visual, and ambience")
            }
        }

        var assetIDs = Set<String>()
        var assetPaths = Set<String>()
        for asset in assets {
            guard assetIDs.insert(asset.id).inserted else {
                throw ValidationError.duplicateAssetID(asset.id)
            }
            guard assetPaths.insert(asset.relativePath).inserted else {
                throw ValidationError.duplicateAssetPath(asset.relativePath)
            }
            guard !asset.id.isEmpty,
                  !asset.kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !asset.contentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !asset.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.invalidProject("asset id, kind, content type, and source are required")
            }
            guard Self.isSafeRelativePath(asset.relativePath) else {
                throw ValidationError.invalidPath(asset.relativePath)
            }
            guard asset.bytes >= 0, Self.isValidSHA256(asset.sha256) else {
                throw ValidationError.invalidChecksum(asset.sha256)
            }
        }

        var shotIDs = Set<String>()
        var shotOrders = Set<Int>()
        for shot in shots {
            guard shotIDs.insert(shot.id).inserted else {
                throw ValidationError.duplicateShotID(shot.id)
            }
            guard shotOrders.insert(shot.order).inserted else {
                throw ValidationError.duplicateShotOrder(shot.order)
            }
            let end = shot.timelineStartMilliseconds.addingReportingOverflow(shot.durationMilliseconds)
            guard shot.order >= 0,
                  shot.timelineStartMilliseconds >= 0,
                  shot.durationMilliseconds > 0,
                  !end.overflow,
                  end.partialValue <= project.durationMilliseconds,
                  shot.take >= 1,
                  shot.seed >= 0,
                  !shot.id.isEmpty,
                  !shot.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shot.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shot.framePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !shot.locationId.isEmpty,
                  shot.transition == "cut" || shot.transition == "fade" else {
                throw ValidationError.invalidShot(shot.id)
            }
            guard Set(shot.characterIds).count == shot.characterIds.count else {
                throw ValidationError.invalidShot(shot.id)
            }
            for characterID in shot.characterIds where !castIDs.contains(characterID) {
                throw ValidationError.unknownCharacter(characterID)
            }
            guard locationIDs.contains(shot.locationId) else {
                throw ValidationError.unknownLocation(shot.locationId)
            }
            if let id = shot.keyframeAssetId {
                guard let referenced = asset(id: id) else {
                    throw ValidationError.missingAssetReference(id)
                }
                guard referenced.kind == "shot-keyframe" else {
                    throw ValidationError.invalidAssetKind(id)
                }
            }
            if let id = shot.clipAssetId {
                guard let referenced = asset(id: id) else {
                    throw ValidationError.missingAssetReference(id)
                }
                guard referenced.kind == "shot-clip" else {
                    throw ValidationError.invalidAssetKind(id)
                }
            }
            for line in shot.dialogue {
                guard line.startSeconds.isFinite,
                      line.startSeconds >= 0,
                      line.startSeconds < shot.durationSeconds,
                      shot.characterIds.contains(line.speaker),
                      !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !line.delivery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.invalidShot(shot.id)
                }
            }
            for cue in shot.soundEffects {
                guard cue.startSeconds.isFinite,
                      cue.startSeconds >= 0,
                      cue.startSeconds < shot.durationSeconds,
                      cue.durationSeconds.isFinite,
                      cue.durationSeconds > 0,
                      cue.durationSeconds <= shot.durationSeconds,
                      cue.levelDb.isFinite,
                      cue.seed >= 0,
                      !cue.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ValidationError.invalidShot(shot.id)
                }
            }
        }

        let expectedOrders = Set(0..<shots.count)
        guard shotOrders == expectedOrders else {
            throw ValidationError.invalidTimeline("shot order must be contiguous from zero")
        }
        var cursor = 0
        for shot in orderedShots {
            guard shot.timelineStartMilliseconds == cursor else {
                throw ValidationError.invalidTimeline("shot \(shot.id) does not begin at the expected timeline position")
            }
            cursor += shot.durationMilliseconds
        }
        guard cursor == project.durationMilliseconds else {
            throw ValidationError.invalidTimeline("shot durations do not equal the declared project duration")
        }
    }

    public var orderedShots: [Shot] {
        shots.sorted {
            if $0.timelineStartMilliseconds == $1.timelineStartMilliseconds {
                if $0.order == $1.order { return $0.id < $1.id }
                return $0.order < $1.order
            }
            return $0.timelineStartMilliseconds < $1.timelineStartMilliseconds
        }
    }

    public func asset(id: String) -> Asset? {
        assets.first { $0.id == id }
    }

    public var referenceAsset: Asset? {
        for kind in ["delivery-master", "final-master", "rough-cut"] {
            if let asset = assets.last(where: { $0.kind == kind }) {
                return asset
            }
        }
        return nil
    }

    public var scoreAsset: Asset? {
        assets.last { $0.kind == "score" }
    }

    public func projectRootURL(relativeTo handoffURL: URL) throws -> URL {
        guard Self.isSafeProjectRoot(source.projectRoot) else {
            throw ValidationError.invalidPath(source.projectRoot)
        }
        return handoffURL.deletingLastPathComponent()
            .appending(path: source.projectRoot)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    public func resolveAsset(_ asset: Asset, relativeTo handoffURL: URL) throws -> URL {
        try resolveProjectPath(asset.relativePath, relativeTo: handoffURL)
    }

    public func resolveRunManifest(relativeTo handoffURL: URL) throws -> URL {
        try resolveProjectPath(source.runManifest, relativeTo: handoffURL)
    }

    public func resolveProjectPath(_ relativePath: String, relativeTo handoffURL: URL) throws -> URL {
        guard Self.isSafeRelativePath(relativePath) else {
            throw ValidationError.invalidPath(relativePath)
        }
        let root = try projectRootURL(relativeTo: handoffURL)
        let candidate = root.appending(path: relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw ValidationError.invalidPath(relativePath)
        }
        return candidate
    }

    private static func isSafeProjectRoot(_ rawPath: String) -> Bool {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = NSString(string: path).pathComponents
        return !components.contains(".")
    }

    private static func isSafeRelativePath(_ rawPath: String) -> Bool {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~") else { return false }
        let components = NSString(string: path).pathComponents
        return !components.contains("..") && !components.contains(".")
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:"), value.count == 71 else { return false }
        return value.dropFirst(7).allSatisfy { character in
            character.isNumber || ("a"..."f").contains(String(character))
        }
    }
}
