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
        guard let runManifest = model.snapshot?.runManifest else {
            model.errorMessage = PalmierFilmStudioModel.StudioError.noProject.localizedDescription
            return
        }
        guard model.runtime?.filmToolsReady == true else {
            model.errorMessage = "Film Studio tools are required to create an editable Palmier handoff."
            return
        }

        let editorID = ObjectIdentifier(editor)
        guard Self.importsInFlight.insert(editorID).inserted else { return }
        let executable = model.filmToolExecutable
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

                try await import(handoff, runManifest: runManifest, into: editor, timelineName: timelineName)
                model.noticeMessage = "Opened an editable Film Studio timeline with \(handoff.shots.count) current shot\(handoff.shots.count == 1 ? "" : "s")."
            } catch {
                model.errorMessage = error.localizedDescription
                model.noticeMessage = nil
            }
        }
    }

    private func import(
        _ handoff: FilmAnimaticHandoff,
        runManifest: URL,
        into editor: EditorViewModel,
        timelineName: String
    ) async throws {
        let shotURLs = handoff.orderedShots.map { handoff.resolve($0.clipPath, relativeTo: runManifest) }
        let audioURLs = [
            handoff.media.dialogueBed,
            handoff.media.musicBed,
            handoff.media.effectsBed,
        ].compactMap { $0 }.map { handoff.resolve($0, relativeTo: runManifest) }
        let referencePath = handoff.media.deliveryMaster ?? handoff.media.roughCut
        let referenceURL = referencePath.map { handoff.resolve($0, relativeTo: runManifest) }

        var uniqueURLs: [URL] = []
        var seenPaths: Set<String> = []
        for url in shotURLs + audioURLs + [referenceURL].compactMap({ $0 }) {
            let standardized = url.standardizedFileURL
            if seenPaths.insert(standardized.path).inserted {
                uniqueURLs.append(standardized)
            }
        }

        let summary = try await editor.importFinderItems(
            uniqueURLs,
            into: editor.mediaPanelCurrentFolderId,
            finalize: false
        )
        guard summary.assets.count == uniqueURLs.count else {
            throw PalmierFilmStudioModel.StudioError.importRejected
        }

        var assetsByPath: [String: MediaAsset] = [:]
        for asset in summary.assets {
            guard await editor.finalizeImportedAsset(asset, batchManifestUpdate: true) else {
                throw PalmierCoreError.invalidOperation(
                    "Palmier could not read Film Studio media: \(asset.url.lastPathComponent)"
                )
            }
            assetsByPath[asset.url.standardizedFileURL.path] = asset
        }
        editor.flushPendingManifestMetadataUpdates()

        for url in shotURLs {
            guard assetsByPath[url.standardizedFileURL.path] != nil else {
                throw PalmierCoreError.invalidOperation(
                    "The Film Studio handoff is missing \(url.lastPathComponent)."
                )
            }
        }

        let timelineID = editor.createTimeline(name: timelineName, activate: true)
        guard editor.activeTimelineId == timelineID else {
            throw PalmierCoreError.invalidOperation("Palmier could not activate the Film Studio timeline.")
        }

        let pictureTrack = editor.insertTrack(at: 0, type: .video)
        if editor.timeline.tracks.indices.contains(pictureTrack) {
            try? editor.setTrackName(id: editor.timeline.tracks[pictureTrack].id, to: handoff.timeline.tracks.picture)
        }

        let fps = max(1.0, Double(editor.timeline.fps))
        for shot in handoff.orderedShots {
            let url = handoff.resolve(shot.clipPath, relativeTo: runManifest)
            guard let asset = assetsByPath[url.standardizedFileURL.path] else { continue }
            let startFrame = max(0, Int((shot.timeline.startSeconds * fps).rounded()))
            let segmentStart = shot.timeline.trimInSeconds
            let segmentEnd = segmentStart + shot.timeline.durationSeconds
            editor.addClips(
                assets: [asset],
                trackIndex: pictureTrack,
                startFrame: startFrame,
                segments: [asset.id: segmentStart...segmentEnd]
            )
        }

        try addAudioBed(
            handoff.media.dialogueBed,
            trackName: handoff.timeline.tracks.dialogue,
            handoff: handoff,
            runManifest: runManifest,
            assetsByPath: assetsByPath,
            editor: editor
        )
        try addAudioBed(
            handoff.media.musicBed,
            trackName: handoff.timeline.tracks.music,
            handoff: handoff,
            runManifest: runManifest,
            assetsByPath: assetsByPath,
            editor: editor
        )
        try addAudioBed(
            handoff.media.effectsBed,
            trackName: handoff.timeline.tracks.effects,
            handoff: handoff,
            runManifest: runManifest,
            assetsByPath: assetsByPath,
            editor: editor
        )

        editor.currentFrame = 0
        editor.revealTimelineTabBarIfMultiple()
        editor.notifyTimelineChanged(refreshVisuals: false)
    }

    private func addAudioBed(
        _ relativePath: String?,
        trackName: String,
        handoff: FilmAnimaticHandoff,
        runManifest: URL,
        assetsByPath: [String: MediaAsset],
        editor: EditorViewModel
    ) throws {
        guard let relativePath else { return }
        let url = handoff.resolve(relativePath, relativeTo: runManifest)
        guard let asset = assetsByPath[url.standardizedFileURL.path] else {
            throw PalmierCoreError.invalidOperation("The Film Studio handoff is missing \(url.lastPathComponent).")
        }
        let trackIndex = editor.insertTrack(at: editor.timeline.tracks.count, type: .audio)
        editor.addClips(assets: [asset], trackIndex: trackIndex, startFrame: 0)
        if editor.timeline.tracks.indices.contains(trackIndex) {
            try? editor.setTrackName(id: editor.timeline.tracks[trackIndex].id, to: trackName)
        }
    }

    private func handoffTimelineName(_ handoff: FilmAnimaticHandoff) -> String {
        let signature = handoff.orderedShots.map {
            "\($0.shotId)|\($0.take)|\($0.clipPath)|\($0.timeline.startSeconds)|\($0.timeline.durationSeconds)|\($0.timeline.trimInSeconds)|\($0.timeline.trimOutSeconds)"
        }.joined(separator: "\n")
        return "Film Studio — \(handoff.project.title) [\(stableShortHash(signature))]"
    }

    private func stableShortHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(String(hash, radix: 16).suffix(8))
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