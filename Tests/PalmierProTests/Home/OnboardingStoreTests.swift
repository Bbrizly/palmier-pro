import Foundation
import Testing
@testable import PalmierPro

@Suite("Onboarding store")
@MainActor
struct OnboardingStoreTests {
    @Test func newUserStartsAtWelcome() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)

            #expect(!store.isComplete)
            #expect(store.step == .welcome)
            #expect(!store.canGoBack)
            #expect(!store.isLastStep)
            #expect(store.progress == 1.0 / Double(OnboardingStep.count))
        }
    }

    @Test func completedUserSkipsAutomaticOnboarding() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: OnboardingStore.completionKey)

            let store = OnboardingStore(defaults: defaults)

            #expect(store.isComplete)
            #expect(store.step == .welcome)
        }
    }

    @Test func advancesThroughEveryStepAndClampsAtEnd() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)

            for expectedStep in OnboardingStep.allCases.dropFirst() {
                store.advance()
                #expect(store.step == expectedStep)
            }

            #expect(store.isLastStep)
            #expect(store.progress == 1)

            store.advance()
            #expect(store.step == .workflows)
        }
    }

    @Test func backNavigationClampsAtWelcome() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)

            store.goBack()
            #expect(store.step == .welcome)

            store.advance()
            #expect(store.canGoBack)

            store.goBack()
            #expect(store.step == .welcome)
            #expect(!store.canGoBack)
        }
    }

    @Test func completionPersists() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.advance()

            store.complete()

            #expect(store.isComplete)
            #expect(defaults.bool(forKey: OnboardingStore.completionKey))
            #expect(OnboardingStore(defaults: defaults).isComplete)
        }
    }

    @Test func skipPersistsCompletion() throws {
        try withDefaults { defaults in
            let store = OnboardingStore(defaults: defaults)
            store.advance()

            store.skip()

            #expect(store.isComplete)
            #expect(defaults.bool(forKey: OnboardingStore.completionKey))
        }
    }

    @Test func replayIsSessionOnlyAndResetsToWelcome() throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: OnboardingStore.completionKey)
            let store = OnboardingStore(defaults: defaults)
            store.advance()
            store.advance()

            store.replay()

            #expect(!store.isComplete)
            #expect(store.step == .welcome)
            #expect(defaults.bool(forKey: OnboardingStore.completionKey))
            #expect(OnboardingStore(defaults: defaults).isComplete)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "OnboardingStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
