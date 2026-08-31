import AppKit
import FilmStudioCore
import SwiftUI

@MainActor
struct FilmStudioPalmierBridge {
    private static var importsInFlight: Set<ObjectIdentifier> = []

    func importPlayableCut(using model: PalmierFilmStudioModel) {
        guard let editor = AppState.shared.activeProject?.editorViewModel else {
            model.errorMessage = PalmierFilmStudioModel.StudioError.noPalmierProject.localizedDescription
            return
        }
        guard let snapshot = model.snapshot else {
            model.errorMessage = PalmierFilmStudioModel.StudioError.noProject.localizedDescription
            return
        }
        guard model.runtime?.filmToolsReady == true else {
            model.errorMessage = "Film Studio tools are required to create an editable Palmier handoff."
            return
        }

        let editorID = ObjectIdentifier(editor)
        guard Self.importsInFlight.insert(editorID).inserted else {
            model.noticeMessage = "The editable Film Studio timeline is already being prepared."
            return
        }
        let executable = model.filmToolExecutable
        let runManifest = snapshot.runManifest
        let projectRoot = snapshot.root
        model.errorMessage = nil
        model.noticeMessage = "Preparing editable Palmier timeline…"

        Task { @MainActor [weak editor, weak model] in
            defer { Self.importsInFlight.remove(editorID) }
            guard let editor, let model else { return }
            do {
                let handoff = try await FilmStudioService.exportAnimaticHandoff(
                    runManifest: runManifest,
                    filmToolExecutable: executable
                )
                let timelineName = handoffTimelineName(handoff)
                if let existing = editor.timelines.first(where: { $0.name == timelineName }) {
                    editor.activateTimeline(existing.id)
                    model.noticeMessage = "Opened the existing editable Film Studio timeline."
                    return
                }

                try await import(handoff, projectRoot: projectRoot, into: editor, timelineName: timelineName)
                let conformNote = editor.timeline.fps == handoff.project.fps
                    ? ""
                    : " Timing was conformed to the Palmier project at \(editor.timeline.fps) fps."
                model.noticeMessage = "Opened an editable Film Studio timeline with \(handoff.shots.count) shot\(handoff.shots.count == 1 ? "" : "s").\(conformNote)"
            } catch is CancellationError {
                model.noticeMessage = nil
            } catch {
                model.errorMessage = error.localizedDescription
                model.noticeMessage = nil
            }
        }
    }

    private struct AudioPlacement {
        let asset: FilmAnimaticHandoff.Asset
        let startSeconds: Double
        let durationSeconds: Double?
    }

    private func import(
        _ handoff: FilmAnimaticHandoff,
        projectRoot: URL,
        into editor: EditorViewModel,
        timelineName: String
    ) async throws {
        try Task.checkCancellation()
        try handoff.validate()

        let pictureAssets = try handoff.orderedShots.map { shot -> FilmAnimaticHandoff.Asset in
            guard let assetID = shot.clipAssetId,
                  let asset = handoff.asset(id: assetID),
                  asset.kind == "shot-clip" else {
                throw PalmierCoreError.invalidOperation("Film Studio shot \(shot.id) has no selected clip.")
            }
            return asset
        }
        let dialogue = dialoguePlacements(in: handoff)
        let effects = effectPlacements(in: handoff)
        let score = handoff.scoreAsset
        let reference = handoff.referenceAsset

        var requiredAssets = pictureAssets + dialogue.map(\.asset) + effects.map(\.asset)
        if let score { requiredAssets.append(score) }
        if let reference { requiredAssets.append(reference) }
        requiredAssets = uniqueAssets(requiredAssets)

        let resolvedProjectRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        func url(for asset: FilmAnimaticHandoff.Asset) -> URL {
            resolvedProjectRoot.appending(path: asset.relativePath).standardizedFileURL
        }

        var mediaByPath: [String: MediaAsset] = [:]
        for asset in editor.mediaAssets {
            mediaByPath[asset.url.standardizedFileURL.path] = asset
        }

        let missingAssets = requiredAssets.filter { mediaByPath[url(for: $0).path] == nil }
        if !missingAssets.isEmpty {
            let missingURLs = missingAssets.map(url(for:))
            let summary = try await editor.importFinderItems(
                missingURLs,
                into: editor.mediaPanelCurrentFolderId,
                finalize: false
            )
            guard summary.assets.count == missingURLs.count else {
                throw PalmierFilmStudioModel.StudioError.importRejected
            }
            for asset in summary.assets {
                mediaByPath[asset.url.standardizedFileURL.path] = asset
            }
        }

        var mediaByHandoffID: [String: MediaAsset] = [:]
        var finalizedMediaIDs = Set<String>()
        for handoffAsset in requiredAssets {
            try Task.checkCancellation()
            let assetURL = url(for: handoffAsset)
            guard let media = mediaByPath[assetURL.path] ?? editor.mediaAssets.first(where: {
                $0.url.standardizedFileURL.path == assetURL.path
            }) else {
                throw PalmierCoreError.invalidOperation(
                    "The Film Studio handoff is missing \(handoffAsset.relativePath)."
                )
            }
            if finalizedMediaIDs.insert(media.id).inserted {
                guard await editor.finalizeImportedAsset(media, batchManifestUpdate: true) else {
                    throw PalmierCoreError.invalidOperation(
                        "Palmier could not read Film Studio media: \(media.url.lastPathComponent)"
                    )
                }
            }
            mediaByHandoffID[handoffAsset.id] = media
        }
        editor.flushPendingManifestMetadataUpdates()

        let timelineID = editor.createTimeline(name: timelineName, activate: true)
        guard editor.activeTimelineId == timelineID else {
            throw PalmierCoreError.invalidOperation("Palmier could not activate the Film Studio timeline.")
        }

        let pictureTrack = editor.insertTrack(at: 0, type: .video)
        guard editor.timeline.tracks.indices.contains(pictureTrack) else {
            throw PalmierCoreError.invalidOperation("Palmier could not create the Film Studio picture track.")
        }
        let pictureTrackID = editor.timeline.tracks[pictureTrack].id
        try? editor.setTrackName(id: pictureTrackID, to: "Film Studio · Picture")

        let fps = max(1.0, Double(editor.timeline.fps))
        let hasEmbeddedClipAudio = pictureAssets.contains { asset in
            mediaByHandoffID[asset.id]?.hasAudio == true
        }
        let clipAudioTrackID: String? = hasEmbeddedClipAudio
            ? makeAudioTrack(named: "Film Studio · Clip Audio", editor: editor)
            : nil

        for (shot, handoffAsset) in zip(handoff.orderedShots, pictureAssets) {
            try Task.checkCancellation()
            guard let media = mediaByHandoffID[handoffAsset.id],
                  let pictureIndex = editor.timeline.tracks.firstIndex(where: { $0.id == pictureTrackID }) else {
                throw PalmierCoreError.invalidOperation("Palmier lost the Film Studio picture track during import.")
            }
            let startFrame = frame(forSeconds: shot.timelineStartSeconds, fps: fps)
            let sourceDuration = media.resolvedDuration > 0
                ? min(shot.durationSeconds, media.resolvedDuration)
                : shot.durationSeconds
            guard sourceDuration > 0 else {
                throw PalmierCoreError.invalidOperation("Film Studio shot \(shot.id) has no usable duration.")
            }
            let linkedAudioIndex = media.hasAudio ? clipAudioTrackID.flatMap { id in
                editor.timeline.tracks.firstIndex(where: { $0.id == id })
            } : nil
            editor.addClips(
                assets: [media],
                trackIndex: pictureIndex,
                startFrame: startFrame,
                linkedAudioTrackIndex: linkedAudioIndex,
                segments: [media.id: 0...sourceDuration]
            )
        }

        try addAudioPlacements(
            dialogue,
            trackName: "Film Studio · Dialogue",
            mediaByHandoffID: mediaByHandoffID,
            editor: editor,
            fps: fps
        )
        try addAudioPlacements(
            effects,
            trackName: "Film Studio · Effects",
            mediaByHandoffID: mediaByHandoffID,
            editor: editor,
            fps: fps
        )
        if let score, let media = mediaByHandoffID[score.id] {
            try addAudioPlacements(
                [AudioPlacement(asset: score, startSeconds: 0, durationSeconds: nil)],
                trackName: "Film Studio · Score",
                mediaByHandoffID: [score.id: media],
                editor: editor,
                fps: fps
            )
        }

        let markers = handoff.orderedShots.map { shot in
            let rawComment = "\(shot.purpose)\nTake \(shot.take) · \(shot.transition)"
            return TimelineMarker(
                name: String(shot.id.prefix(TimelineMarker.maximumNameLength)),
                startFrame: frame(forSeconds: shot.timelineStartSeconds, fps: fps),
                durationFrames: max(1, frame(forSeconds: shot.durationSeconds, fps: fps)),
                comment: String(rawComment.prefix(TimelineMarker.maximumCommentLength))
            )
        }
        do {
            _ = try editor.changeTimelineMarkers(creates: markers, actionName: "Import Film Studio Markers")
        } catch {
            throw PalmierCoreError.invalidOperation("Palmier could not create Film Studio shot markers.")
        }

        editor.currentFrame = 0
        editor.revealTimelineTabBarIfMultiple()
        editor.notifyTimelineChanged(refreshVisuals: false)
    }

    private func makeAudioTrack(named name: String, editor: EditorViewModel) -> String? {
        let inserted = editor.insertTrack(at: editor.timeline.tracks.count, type: .audio)
        guard editor.timeline.tracks.indices.contains(inserted) else { return nil }
        let trackID = editor.timeline.tracks[inserted].id
        try? editor.setTrackName(id: trackID, to: name)
        return trackID
    }

    private func addAudioPlacements(
        _ placements: [AudioPlacement],
        trackName: String,
        mediaByHandoffID: [String: MediaAsset],
        editor: EditorViewModel,
        fps: Double
    ) throws {
        guard !placements.isEmpty else { return }
        guard let trackID = makeAudioTrack(named: trackName, editor: editor) else {
            throw PalmierCoreError.invalidOperation("Palmier could not create \(trackName).")
        }

        for placement in placements {
            guard let media = mediaByHandoffID[placement.asset.id],
                  let trackIndex = editor.timeline.tracks.firstIndex(where: { $0.id == trackID }) else {
                throw PalmierCoreError.invalidOperation("Palmier could not place \(placement.asset.relativePath).")
            }
            var segments: [String: ClosedRange<Double>] = [:]
            if let requestedDuration = placement.durationSeconds {
                let sourceDuration = media.resolvedDuration > 0
                    ? min(requestedDuration, media.resolvedDuration)
                    : requestedDuration
                guard sourceDuration > 0 else {
                    throw PalmierCoreError.invalidOperation("Film Studio audio has no usable duration: \(placement.asset.relativePath)")
                }
                segments[media.id] = 0...sourceDuration
            }
            editor.addClips(
                assets: [media],
                trackIndex: trackIndex,
                startFrame: frame(forSeconds: placement.startSeconds, fps: fps),
                segments: segments
            )
        }
    }

    private func dialoguePlacements(in handoff: FilmAnimaticHandoff) -> [AudioPlacement] {
        var placements: [AudioPlacement] = []
        for shot in handoff.orderedShots {
            let slug = filmSlug(shot.id)
            for (index, line) in shot.dialogue.enumerated() {
                let path = "audio/dialogue/\(slug)-\(String(format: "%02d", index + 1)).wav"
                guard let asset = handoff.assets.first(where: {
                    $0.kind == "dialogue" && $0.relativePath == path
                }) else { continue }
                placements.append(
                    AudioPlacement(
                        asset: asset,
                        startSeconds: shot.timelineStartSeconds + line.startSeconds,
                        durationSeconds: nil
                    )
                )
            }
        }
        return placements
    }

    private func effectPlacements(in handoff: FilmAnimaticHandoff) -> [AudioPlacement] {
        var placements: [AudioPlacement] = []
        for shot in handoff.orderedShots {
            let slug = filmSlug(shot.id)
            for (index, cue) in shot.soundEffects.enumerated() {
                let path = "audio/sfx/\(slug)-\(String(format: "%02d", index + 1)).wav"
                guard let asset = handoff.assets.first(where: {
                    $0.kind == "sound-effect" && $0.relativePath == path
                }) else { continue }
                placements.append(
                    AudioPlacement(
                        asset: asset,
                        startSeconds: shot.timelineStartSeconds + cue.startSeconds,
                        durationSeconds: cue.durationSeconds
                    )
                )
            }
        }
        return placements
    }

    private func uniqueAssets(_ assets: [FilmAnimaticHandoff.Asset]) -> [FilmAnimaticHandoff.Asset] {
        var seen = Set<String>()
        return assets.filter { seen.insert($0.id).inserted }
    }

    private func frame(forSeconds seconds: Double, fps: Double) -> Int {
        max(0, Int((seconds * fps).rounded()))
    }

    private func handoffTimelineName(_ handoff: FilmAnimaticHandoff) -> String {
        var components = [
            handoff.contractVersion,
            handoff.source.projectId,
            String(handoff.project.fps),
            String(handoff.project.durationMilliseconds),
            handoff.project.aspectRatio,
            String(handoff.project.width ?? 0),
            String(handoff.project.height ?? 0),
        ]
        for shot in handoff.orderedShots {
            components.append(contentsOf: [
                shot.id,
                String(shot.order),
                String(shot.timelineStartMilliseconds),
                String(shot.durationMilliseconds),
                String(shot.take),
                String(shot.seed),
                shot.transition,
                shot.clipAssetId ?? "",
            ])
            if let assetID = shot.clipAssetId, let asset = handoff.asset(id: assetID) {
                components.append(asset.sha256)
            }
        }
        let editorialKinds: Set<String> = [
            "dialogue", "sound-effect", "score",
            "rough-cut", "final-master", "delivery-master",
        ]
        for asset in handoff.assets.filter({ editorialKinds.contains($0.kind) }).sorted(by: { $0.id < $1.id }) {
            components.append(contentsOf: [asset.id, asset.kind, asset.relativePath, asset.sha256])
        }
        let signature = components.joined(separator: "\u{1F}")
        let cleanTitle = handoff.project.title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "Film Studio — \(cleanTitle) [\(stableHash(signature))]"
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private func filmSlug(_ value: String) -> String {
        var output = ""
        var pendingDash = false
        for scalar in value.lowercased().unicodeScalars {
            let isLetter = scalar.value >= 97 && scalar.value <= 122
            let isDigit = scalar.value >= 48 && scalar.value <= 57
            if isLetter || isDigit {
                if pendingDash && !output.isEmpty { output.append("-") }
                output.append(Character(String(scalar)))
                pendingDash = false
            } else {
                pendingDash = true
            }
            if output.count >= 64 { break }
        }
        return output.isEmpty ? "film" : String(output.prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

@MainActor
final class FilmStudioWindowController: NSWindowController {
    static let shared = FilmStudioWindowController()

    private let model: PalmierFilmStudioModel

    private init() {
        let model = PalmierFilmStudioModel()
        self.model = model
        let rootView = FilmStudioWorkspaceView(
            model: model,
            bridge: FilmStudioPalmierBridge()
        )
        .appLocalization()
        .tint(AppTheme.Accent.primary)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Palmier Film Studio"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(AppTheme.Window.settingsDefault)
        window.minSize = AppTheme.Window.settingsMin
        window.backgroundColor = AppTheme.Background.base
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PalmierFilmStudioWindow")
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        model.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
