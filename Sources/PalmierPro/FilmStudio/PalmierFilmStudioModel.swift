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
        case unknownShot(String)

        var errorDescription: String? {
            switch self {
            case .noProject:
                "Open or create a film first."
            case .noPlayableCut:
                "GRACE has not produced a playable cut yet."
            case .noPalmierProject:
                "Open a Palmier project before opening the editable Film Studio timeline."
            case .importRejected:
                "Palmier could not import one or more verified Film Studio assets. Check that the generated files are supported media types."
            case .setupIncomplete:
                "Finish the setup required for this Film Studio action, then retry."
            case .unknownShot(let id):
                "The Film Studio project no longer contains shot \(id). Refresh the project and retry."
            }
        }
    }

    private enum AdvanceRequirement {
        case agent
        case media
        case agentAndMedia
        case blocked
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
    private var runtimeRefreshID = UUID()
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

    var hasPendingReviewRequests: Bool {
        snapshot?.project.reviewRequests.contains { $0.status == "pending" } == true
    }

    var needsHumanReviewDecision: Bool {
        guard pendingGate == "picture-lock",
              !hasPendingReviewRequests,
              let proof = snapshot?.project.proof else { return false }
        return proof.review && !proof.humanReview
    }

    var planningReady: Bool { runtime?.planningReady == true }
    var agentReady: Bool { runtime?.agentReady == true }
    var mediaReady: Bool { runtime?.planningReady == true && runtime?.mediaToolsReady == true }
    var productionReady: Bool { runtime?.productionReady == true }
    var canCreateFilm: Bool { planningReady && !isBusy }

    var canApprove: Bool {
        guard snapshot != nil,
              let gate = pendingGate,
              !briefNeedsInput,
              runtime?.filmToolsReady == true,
              !isBusy else { return false }

        switch gate {
        case "production":
            return !productionNeedsConfiguration && mediaReady
        case "picture-lock":
            return snapshot?.project.proof.humanReview == true && !hasPendingReviewRequests
        default:
            return true
        }
    }

    var canAdvance: Bool {
        guard snapshot != nil,
              pendingGate == nil,
              !isCompleted,
              !isBusy else { return false }
        switch advanceRequirement {
        case .agent:
            return agentReady
        case .media:
            return mediaReady
        case .agentAndMedia:
            return productionReady
        case .blocked:
            return false
        }
    }

    var canReroll: Bool {
        snapshot != nil
            && runtime?.filmToolsReady == true
            && !isCompleted
            && !isBusy
    }

    var hasInterruptedWork: Bool {
        guard let project = snapshot?.project else { return false }
        return project.status == "running"
            || project.departments.contains { $0.status == "running" }
            || project.jobs.contains { $0.status == "running" }
    }

    private var advanceRequirement: AdvanceRequirement {
        guard let project = snapshot?.project else { return .blocked }
        if project.approvals["treatment"]?.status != "approved" {
            return .agent
        }
        if project.approvals["production"]?.status != "approved" {
            return .agent
        }
        if !project.proof.assembly {
            return .media
        }
        if !project.proof.review {
            return project.status == "revision-required" ? .blocked : .agentAndMedia
        }
        if project.approvals["picture-lock"]?.status == "approved", !project.proof.delivery {
            return .media
        }
        return .blocked
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
        let folder = slug.isEmpty ? "untitled-film" : String(slug.prefix(80))
        return newFilmDirectory.appending(path: folder, directoryHint: .isDirectory)
    }

    func activate() {
        Task { @MainActor [weak self] in
            await self?.refreshRuntime()
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
        panel.message = "Choose a GRACE run manifest JSON."
        panel.prompt = "Open Film"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openProject(url)
    }

    func chooseNewFilmDirectory() {
        guard !isBusy else { return }
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
        let runManifest = resolvedRunManifestInput(input)
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
                guard self.projectLoadID == requestID else { return }
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
        runtimeRefreshID = UUID()
        let requestID = runtimeRefreshID
        let filmToolExecutable = filmToolExecutable
        let mereRunExecutable = mereRunExecutable
        isRuntimeRefreshing = true
        let inspected = await FilmStudioService.inspectRuntime(
            filmToolExecutable: filmToolExecutable,
            mereRunExecutable: mereRunExecutable
        )
        guard runtimeRefreshID == requestID else { return }
        runtime = inspected
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

    func configurePiProvider() {
        guard !isBusy,
              runtime?.mereRunReady == true,
              let modelID = runtime?.selectedAgentModel?.id else { return }
        let mereRunExecutable = mereRunExecutable
        runSetupRepair(
            activity: "Configuring Pi for mere.run…",
            success: "Pi is configured for the selected local producer model."
        ) {
            try await FilmStudioService.configurePiProvider(
                mereRunExecutable: mereRunExecutable,
                modelID: modelID
            )
        }
    }

    func copyModelSetupCommand() {
        guard let runtime else { return }
        copyToPasteboard(FilmStudioService.modelSetupCommand(runtime: runtime, mereRunExecutable: mereRunExecutable))
        noticeMessage = runtime.recommendedModel == nil
            ? "Copied the Mere producer setup command."
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
                } catch is CancellationError {
                    return
                } catch {
                    await self.reloadCurrentProject(reportErrors: false)
                    self.errorMessage = "Production settings were saved, but model preflight failed. \(error.localizedDescription)"
                }
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func recordReviewDecision(
        decision: String,
        note: String,
        rerolls: [FilmStudioReviewReroll]
    ) {
        guard !isBusy,
              pendingGate == "picture-lock",
              let runManifest = snapshot?.runManifest,
              let filmToolPath = runtime?.filmToolPath else { return }
        let reviewer = NSFullUserName().isEmpty ? "macOS user" : NSFullUserName()
        beginActivity(decision == "approve" ? "Recording cut approval…" : "Recording revision request…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                try await FilmStudioService.recordReviewDecision(
                    runManifest: runManifest,
                    decision: decision,
                    reviewer: reviewer,
                    note: note,
                    rerolls: rerolls,
                    filmToolPath: filmToolPath
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = decision == "approve"
                    ? "Human review is recorded against this exact cut. Picture lock is ready for approval."
                    : "Revision requests are recorded. Prepare each requested reroll before continuing."
            } catch is CancellationError {
                return
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
        let filmToolPath = runtime?.filmToolPath
        let approvedBy = NSFullUserName().isEmpty ? "macOS user" : NSFullUserName()
        beginActivity("Approving \(displayName(gate))…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                if gate == "production" {
                    guard let filmToolPath else { throw StudioError.setupIncomplete }
                    try await FilmStudioService.preflightProduction(
                        runManifest: runManifest,
                        filmToolPath: filmToolPath
                    )
                }
                try await FilmStudioService.approve(
                    runManifest: runManifest,
                    gate: gate,
                    approvedBy: approvedBy,
                    filmToolExecutable: filmToolExecutable
                )
                await self.reloadCurrentProject(reportErrors: true)
                self.noticeMessage = self.isCompleted
                    ? "Film completed. The verified master is ready for Palmier."
                    : "Approved \(self.displayName(gate)). You can continue production."
            } catch is CancellationError {
                return
            } catch {
                await self.reloadCurrentProject(reportErrors: false)
                self.errorMessage = gate == "production"
                    ? "Production readiness changed before approval. \(error.localizedDescription)"
                    : error.localizedDescription
            }
        }
    }

    func advance() {
        guard canAdvance,
              let runManifest = snapshot?.runManifest,
              let filmToolPath = runtime?.filmToolPath else {
            errorMessage = StudioError.setupIncomplete.localizedDescription
            return
        }
        let requirement = advanceRequirement
        let filmToolExecutable = filmToolExecutable
        let mereRunExecutable = mereRunExecutable
        beginActivity("Continuing production…")
        commandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.endActivity() }
            do {
                switch requirement {
                case .agent, .agentAndMedia:
                    try await FilmStudioService.advance(
                        runManifest: runManifest,
                        filmToolExecutable: filmToolExecutable,
                        mereRunExecutable: mereRunExecutable
                    )
                case .media:
                    try await FilmStudioService.advanceWithoutAgent(
                        runManifest: runManifest,
                        filmToolPath: filmToolPath
                    )
                case .blocked:
                    throw StudioError.setupIncomplete
                }
                await self.reloadCurrentProject(reportErrors: true)
                if let gate = self.pendingGate {
                    self.noticeMessage = "Production stopped for \(self.displayName(gate)) approval."
                } else if self.isCompleted {
                    self.noticeMessage = "Film completed. The verified master is ready for Palmier."
                } else {
                    self.noticeMessage = "Production advanced."
                }
            } catch is CancellationError {
                await self.reloadCurrentProject(reportErrors: false)
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
        guard snapshot?.productionPlan?.shots.contains(where: { $0.id == shotID }) == true else {
            errorMessage = StudioError.unknownShot(shotID).localizedDescription
            return
        }
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
                self.noticeMessage = "\(shotID) is prepared for a targeted reroll. Continue production when the requested revisions are resolved."
            } catch is CancellationError {
                return
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func recover() {
        guard !isBusy,
              let runManifest = snapshot?.runManifest else {
            errorMessage = StudioError.noProject.localizedDescription
            return
        }
        guard runtime?.filmToolsReady == true else {
            errorMessage = StudioError.setupIncomplete.localizedDescription
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
            } catch is CancellationError {
                return
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
            } catch is CancellationError {
                return
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
        } catch is CancellationError {
            return
        } catch {
            if reportErrors { errorMessage = error.localizedDescription }
        }
    }

    private func resolvedRunManifestInput(_ input: URL) -> URL {
        let standardized = input.standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return standardized.appending(path: "run.json").standardizedFileURL
        }
        return standardized
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
