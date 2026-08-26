import Foundation
import Observation

@MainActor @Observable
final class OnboardingStore {
    static let completionKey = "nativeAIOnboardingCompleted"
    static let shared = OnboardingStore()

    private(set) var step = OnboardingStep.welcome
    private(set) var isComplete: Bool
    private(set) var selectedWorkflow: OnboardingWorkflow?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isComplete = defaults.bool(forKey: Self.completionKey)
    }

    var canGoBack: Bool {
        step != .welcome
    }

    var isLastStep: Bool {
        step == .workflows
    }

    var progress: Double {
        Double(step.position) / Double(OnboardingStep.count)
    }

    func advance() {
        guard let destination = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = destination
    }

    func goBack() {
        guard let destination = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = destination
    }

    func selectWorkflow(_ workflow: OnboardingWorkflow) {
        selectedWorkflow = workflow
    }

    func complete() {
        defaults.set(true, forKey: Self.completionKey)
        isComplete = true
    }

    func skip() {
        complete()
    }

    func replay() {
        step = .welcome
        selectedWorkflow = nil
        isComplete = false
    }

    func openComputeSetup() {
        FilmStudioWindowController.shared.show()
    }

    func finishAndCreateProject() {
        complete()
        AppState.shared.createProjectInteractively()
    }
}
