import AppKit
import Combine
import FilmStudioCore
import Foundation

@MainActor
final class PalmierFilmStudioModel: ObservableObject {
    enum StudioError: LocalizedError {
        case noProject
        case noPlayableCut
        case noPalmierProject
        case importRejected
        case setupIncomplete

        var errorDescription: String? {
            switch self {
            case .noProject:
                "Open or create a film first."
            case .noPlayableCut:
                "GRACE has not produced a playable cut yet."
            case .noPalmierProject:
                "Open a Palmier project before importing the GRACE cut."
            case .importRejected:
                "Palmier did not import the GRACE cut. Check that the generated file is a supported media type."
            case .setupIncomplete:
                "Finish Film Studio setup before starting or advancing a production."
            }
        }
    }

    @Published private(set) var snapshot: FilmWorkspaceSnapshot?
    @Published private(set) var playableCutURL: URL?
    @Published private(set) var runtime: FilmStudioRuntimeStatus?
    @Published private(set) var isRuntimeRefreshing = false
    @Published private(set) var isBusy = false
    @Published private(set) var activity = ""
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    @Published var filmToolOverride: String {
        didSet { UserDefaults.standard.set(filmToolOverride, forKey: Keys.filmToolOverride) }
    }
    @Published var mereRunOverride: String {
        didSet { UserDefaults.standard.set(mereRunOverride, forKey: Keys.mereRunOverride) }
    }

    @Published var newFilmIdea = ""
    @Published var newFilmTitle = ""
    @Published var newFilmDuration = 45
    @Published var newFilmDirectory = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: "Movies/Palmier Films", directoryHint: .isDirectory)

    let durationOptions = [15, 30, 45, 60, 90, 120]

    private enum Keys {
        static let filmToolOverride = "palmierFilmStudio.filmToolOverride"
        static let mereRunOverride = "palmierFilmStudio.mereRunOverride"
        static let lastRunManifest = "palmierFilmStudio.lastRunManifest"
    }

    private var commandTask: Task<Void, Never>?
    private var projectLoadTask: Task<Void, Never>?
    private var watcherTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var watcher: FilmStudioProjectWatcher?
    private var watchedRoot: URL?
    private var projectLoadID = UUID()
    private var restoredLastProject = false

    init() {
        filmToolOverride = UserDefaults.standard.string(forKey: Keys.filmToolOverride) ?? ""
        mereRunOverride = UserDefaults.standard.string(forKey: Keys.mereRunOverride) ?? ""
    }

    deinit {
        commandTask?.cancel()
        projectLoadTask?.cancel()
        watcherTask?.cancel()
        refreshDebounceTask?.cancel()
    }

    var filmToolExecutable: String {
        let override = filmToolOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? "mere-film-tools" : override
    }

    var mereRunExecutable: String {
        let override = mereRunOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return ProcessInfo.processInfo.environment["MERE_RUN_EXECUTABLE"] ?? "mere.run"
    }

    var pendingGate: String? {
        guard let approvals = snapshot?.project.approvals else { return nil }
        return ["brief", "treatment", "production", "picture-lock", "delivery"]
            .first { approvals[$0]?.status == "pending" }
    }

    var briefNeedsInput: Bool {
        snapshot?.project.brief.openQuestions.isEmpty == false
    }

    var isCompleted: Bool {
        snapshot?.project.status == "completed" || snapshot?.project.phase == "completed"
    }

    var productionModelReadinessBlocked: Bool {
        snapshot?.project.issues.contains { $0.code == "model-readiness" && $0.blocking } == true
    }

    var productionNeedsConfiguration: Bool {
        guard pendingGate == "production", let snapshot else { return false }
        return snapshot.project.production.mode == "plan" || productionModelReadinessBlocked
    }

    var productionReady: Bool { runtime?.productionReady == true }
    var canCreateFilm: Bool { productionReady && !isBusy }
    var canApprove: Bool {
        snapshot != nil
            && pendingGate != nil
            && !briefNeedsInput
            && !productionNeedsConfiguration
            && runtime?.filmToolsReady == true
            && !isBusy
    }
    var canAdvance: Bool {
        snapshot != nil
            && pendingGate == nil
            && productionReady
            && !isCompleted
            && !isBusy
    }
    var canReview: Bool { snapshot != nil && playableCutURL != nil && productionReady && !isBusy }
    var canReroll: Bool { snapshot != nil && runtime?.filmToolsReady == true && !isBusy }
    var hasInterruptedWork: Bool {
        snapshot?.project.jobs.contains { $0.status == "running" } == true
    }

    var effectiveNewFilmTitle: String {
        let title = newFilmTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        let inferred = newFilmIdea.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ")
        return inferred.isEmpty ? "Untitled Film" : inferred
    }

    var newFilmProjectDirectory: URL {
        let slug = effectiveNewFilmTitle.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return newFilmDirectory.appending(
            path: slug.isEmpty ? "untitled-film" : slug,
            directoryHint: .isDirectory
        )
    }

    func activate() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshRuntime()
        }
        guard !restoredLastProject else { return }
        restoredLastProject = true
        guard snapshot == nil,
              let lastRun = UserDefaults.standard.string(forKey: Keys.lastRunManifest) else { return }
        openProject(URL(fileURLWithPath: lastRun), reportErrors: false)
    }

    func chooseProject() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Open Film"
        panel.message = "Choose the run.json for a GRACE film."
        panel.prompt = "Open Film"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }

    func chooseNewFilmDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Film Location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = newFilmDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        newFilmDirectory = url
    }

    func openProject(_ input: URL, reportErrors: Bool = true) {
        guard !isBusy else { return }
        let runManifest = input.lastPathComponent == "run.json"
            ? input.standardizedFileURL
            : input.appending(path: "run.json").standardizedFileURL
        projectLoadTask?.cancel()
        projectLoadID = UUID()
        let requestID = projectLoadID
        projectLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let loaded = try await FilmStudioService.loadProject(runManifest: runManifest)
                try Task.checkCancellation()
                guard self.projectLoadID == requestID else { return }
                self.applyLoadedProject(loaded)
                self.errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                if reportErrors { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func closeProject() {
        guard !isBusy else { return }
        projectLoadTask?.cancel()
        watcherTask?.cancel()
        refreshDebounceTask?.cancel()
        watcher = nil
        watchedRoot = nil
        snapshot = nil
        playableCutURL = nil
        noticeMessage = nil
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: Keys.lastRunManifest)
    }

    func refreshRuntime() async {
        guard !isRuntimeRefreshing else { return }
        isRuntimeRefreshing = true
        let status = await FilmStudioService.inspectRuntime(
            filmToolExecutable: filmToolExecutable,
            mereRunExecutable: mereRunExecutable
        )
        runtime = status
        isRuntimeRefreshing = false
    }

    func installFilmTools() {
        guard !isBusy, runtime?.mereRunReady == true else { return }
        let mereRunExecutable = mereRunExecutable
        runSetupRepair(
            activity: "Installing Film Studio tools…",
            success: "Film Studio tools are installed."
        ) {
            try await FilmStudioService.installFilmTools(mereRunExecutable: mereRunExecutable)
        }
    }

    func installPi() {
        guard !isBusy, runtime?.mereRunReady == true else { return }
        let mereRunExecutable = mereRunExecutable
        runSetupRepair(
            activity: "Installing Pi…",
            success: "Pi is installed."
        ) {
            try await FilmStudioService.installPi(mereRunExecutable: mereRunExecutable)
        }
    }

    func copyModelSetupCommand() {
        guard let runtime else { return }
        copyToPasteboard(FilmStudioService.modelSetupCommand(runtime: runtime, mereRunExecutable: mereRunExecutable))
        noticeMessage = runtime.recommendedModel == nil
            ? "Copied the Mere agent setup command."
            : "Copied the recommended model install command. Review any model terms shown by Mere before accepting them."
    }

    func copyFFmpegInstallCommand() {
        copyToPasteboard("brew install ffmpeg")
        noticeMessage = "Copied: brew install ffmpeg"
    }

    func openMereDownloads() {
        guard let url = URL(string: "https://mere.run/releases") else { return }
        NSWorkspace.shared.open(url)
    }

    func resetExecutableOverrides() {
        filmToolOverride = ""
        mereRunOverride = ""
        Task { @MainActor [weak self] in
            await self?.refreshRuntime()
        }
    }

    func createFilm() {
        guard canCreateFilm else {
            errorMessage = StudioError.setupIncomplete.localizedDescription
            return
        }
        let idea = newFilmIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else {
            errorMessage = "Enter an idea for the film."
            return
        }
        let title = effectiveNewFilmTitle
        let duration = newFilmDuration
        let output = newFilmProjectDirectory
        let filmToolExecutable = filmToolExecutable
        let mereRunExecutable = mereRunExecutable

        beginActivity("Creating film…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                let runManifest = try await FilmStudioService.createFilm(
                    idea: idea,
                    title: title,
                    durationSeconds: duration,
                    outputDirectory: output,
                    filmToolExecutable: filmToolExecutable,
                    mereRunExecutable: mereRunExecutable
                )
                let loaded = try await FilmStudioService.loadProject(runManifest: runManifest)
                self.applyLoadedProject(loaded)
                self.newFilmIdea = ""
                self.newFilmTitle = ""
                self.noticeMessage = "Film created. Complete the brief, then approve it when it looks right."
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func completeBrief(
        audience: String,
        genre: String,
        tone: String,
        rating: String,
        usage: String,
        references: String
    ) {
        guard !isBusy, let runManifest = snapshot?.runManifest else { return }
        let values = [audience, genre, tone, rating, usage]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.allSatisfy({ !$0.isEmpty }) else {
            errorMessage = "Audience, genre, tone, rating, and intended use are required before greenlight."
            return
        }
        let referenceValues = references
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let confirmedReferences = referenceValues.isEmpty ? ["No specific references"] : referenceValues
        let filmToolExecutable = filmToolExecutable

        beginActivity("Updating brief…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.updateBrief(
                    runManifest: runManifest,
                    audience: values[0],
                    genre: values[1],
                    tone: values[2],
                    rating: values[3],
                    usage: values[4],
                    references: confirmedReferences,
                    filmToolExecutable: filmToolExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = self.briefNeedsInput
                    ? "Brief updated. Resolve the remaining questions before approval."
                    : "Brief is complete. Review it, then approve the brief."
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func configureProduction(mode: String, takesPerShot: Int) {
        guard !isBusy,
              pendingGate == "production",
              let runManifest = snapshot?.runManifest,
              let filmToolPath = runtime?.filmToolPath else { return }
        beginActivity("Checking production setup…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.configureProduction(
                    runManifest: runManifest,
                    mode: mode,
                    takesPerShot: takesPerShot,
                    filmToolPath: filmToolPath
                )
                do {
                    try await FilmStudioService.preflightProduction(
                        runManifest: runManifest,
                        filmToolPath: filmToolPath
                    )
                    await self.reloadCurrentProject(reportErrors: true)
                    self.noticeMessage = "Production is configured and the required local models passed preflight. Review the plan, then approve production."
                } catch {
                    await self.reloadCurrentProject(reportErrors: false)
                    self.errorMessage = "Production settings were saved, but model preflight failed. \(error.localizedDescription)"
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func approvePendingGate() {
        guard canApprove,
              let runManifest = snapshot?.runManifest,
              let gate = pendingGate else { return }
        let filmToolExecutable = filmToolExecutable
        let approvedBy = NSFullUserName().isEmpty ? "macOS user" : NSFullUserName()
        beginActivity("Approving \(displayName(gate))…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.approve(
                    runManifest: runManifest,
                    gate: gate,
                    approvedBy: approvedBy,
                    filmToolExecutable: filmToolExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = "Approved \(self.displayName(gate)). You can continue production."
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func advance() {
        guard canAdvance, let runManifest = snapshot?.runManifest else { return }
        let filmToolExecutable = filmToolExecutable
        let mereRunExecutable = mereRunExecutable
        beginActivity("Continuing production…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.advance(
                    runManifest: runManifest,
                    filmToolExecutable: filmToolExecutable,
                    mereRunExecutable: mereRunExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                if let gate = self.pendingGate {
                    self.noticeMessage = "Production stopped for \(self.displayName(gate)) approval."
                } else if self.isCompleted {
                    self.noticeMessage = "Film completed. The verified master is ready for Palmier."
                } else {
                    self.noticeMessage = "Production advanced."
                }
            } catch {
                self.errorMessage = error.localizedDescription
                await self.reloadCurrentProject(reportErrors: false)
            }
        }
    }

    func runReview() {
        guard canReview, let runManifest = snapshot?.runManifest else { return }
        let filmToolExecutable = filmToolExecutable
        let mereRunExecutable = mereRunExecutable
        beginActivity("Reviewing film…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.review(
                    runManifest: runManifest,
                    filmToolExecutable: filmToolExecutable,
                    mereRunExecutable: mereRunExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = "Review finished. Check the findings before approving picture lock."
            } catch {
                self.errorMessage = error.localizedDescription
                await self.reloadCurrentProject(reportErrors: false)
            }
        }
    }

    func reroll(shotID: String, note: String) {
        let reason = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canReroll,
              !reason.isEmpty,
              let runManifest = snapshot?.runManifest else { return }
        let filmToolExecutable = filmToolExecutable
        beginActivity("Preparing \(shotID) reroll…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.reroll(
                    runManifest: runManifest,
                    shotID: shotID,
                    note: reason,
                    filmToolExecutable: filmToolExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = "\(shotID) is queued for a targeted reroll. Continue production when ready."
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func recover() {
        guard !isBusy, let runManifest = snapshot?.runManifest else {
            errorMessage = StudioError.noProject.localizedDescription
            return
        }
        let filmToolExecutable = filmToolExecutable
        beginActivity("Recovering interrupted work…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.recover(
                    runManifest: runManifest,
                    filmToolExecutable: filmToolExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = "Interrupted work was recovered."
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func importPlayableCut(into editor: EditorViewModel) {
        guard !isBusy else { return }
        guard let cutURL = playableCutURL else {
            errorMessage = StudioError.noPlayableCut.localizedDescription
            return
        }
        beginActivity("Importing cut into Palmier…")
        commandTask = Task { @MainActor [weak self, weak editor] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                guard let editor else { throw StudioError.noPalmierProject }
                let summary = try await editor.importFinderItems(
                    [cutURL],
                    into: editor.mediaPanelCurrentFolderId,
                    finalize: true
                )
                guard summary.assetCount > 0 else { throw StudioError.importRejected }
                self.noticeMessage = "Imported \(cutURL.lastPathComponent) into the active Palmier project."
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func openPlayableCut() {
        guard let cutURL = playableCutURL else {
            errorMessage = StudioError.noPlayableCut.localizedDescription
            return
        }
        NSWorkspace.shared.open(cutURL)
    }

    func revealPlayableCut() {
        guard let cutURL = playableCutURL else {
            errorMessage = StudioError.noPlayableCut.localizedDescription
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([cutURL])
    }

    func dismissMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    func displayName(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private func runSetupRepair(
        activity: String,
        success: String,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        guard !isBusy else { return }
        beginActivity(activity)
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await operation()
                await self.refreshRuntime()
                self.noticeMessage = success
            } catch {
                self.errorMessage = error.localizedDescription
                await self.refreshRuntime()
            }
        }
    }

    private func beginActivity(_ description: String) {
        isBusy = true
        activity = description
        errorMessage = nil
        noticeMessage = nil
    }

    private func endActivity() {
        isBusy = false
        activity = ""
        commandTask = nil
    }

    private func applyLoadedProject(_ loaded: FilmStudioLoadedProject) {
        let rootChanged = watchedRoot?.standardizedFileURL != loaded.snapshot.root.standardizedFileURL
        snapshot = loaded.snapshot
        playableCutURL = loaded.playableCutURL
        UserDefaults.standard.set(loaded.snapshot.runManifest.path, forKey: Keys.lastRunManifest)
        if rootChanged {
            installWatcher(root: loaded.snapshot.root)
        }
    }

    private func installWatcher(root: URL) {
        watcherTask?.cancel()
        watcher = nil
        watchedRoot = root.standardizedFileURL
        watcherTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let watcher = await FilmStudioService.makeWatcher(root: root) { [weak self] in
                Task { @MainActor in
                    self?.workspaceDidChange(root: root)
                }
            }
            guard !Task.isCancelled,
                  self.watchedRoot?.standardizedFileURL == root.standardizedFileURL else { return }
            self.watcher = watcher
        }
    }

    private func workspaceDidChange(root: URL) {
        guard !isBusy,
              snapshot?.root.standardizedFileURL == root.standardizedFileURL else { return }
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.reloadCurrentProject(reportErrors: false)
        }
    }

    private func reloadCurrentProject(reportErrors: Bool) async {
        guard let runManifest = snapshot?.runManifest else { return }
        do {
            let loaded = try await FilmStudioService.loadProject(runManifest: runManifest)
            guard snapshot?.runManifest.standardizedFileURL == runManifest.standardizedFileURL else { return }
            applyLoadedProject(loaded)
        } catch {
            if reportErrors { errorMessage = error.localizedDescription }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
