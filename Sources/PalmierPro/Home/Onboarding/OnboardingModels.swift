import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case understanding
    case sharedTimeline
    case direction
    case personalization
    case compute
    case workflows

    var id: Int { rawValue }

    var position: Int { rawValue + 1 }

    static var count: Int { allCases.count }
}

enum OnboardingMode: String, CaseIterable, Identifiable {
    case autopilot
    case copilot
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autopilot: "Autopilot"
        case .copilot: "Copilot"
        case .manual: "Manual"
        }
    }

    var detail: String {
        switch self {
        case .autopilot: "Ask for an editable first draft from your footage."
        case .copilot: "Select a clip or range and tell AI what you want changed."
        case .manual: "Edit normally. AI stays out of your way."
        }
    }

    var symbol: String {
        switch self {
        case .autopilot: "sparkles.rectangle.stack"
        case .copilot: "cursorarrow.motionlines"
        case .manual: "slider.horizontal.3"
        }
    }
}

enum OnboardingWorkflow: String, CaseIterable, Identifiable {
    case shorts
    case talkingHead
    case gaming
    case appDemo
    case empty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shorts: "Make Shorts"
        case .talkingHead: "Talking Head"
        case .gaming: "Gaming / Reactions"
        case .appDemo: "App Demo"
        case .empty: "Start Empty"
        }
    }

    var detail: String {
        switch self {
        case .shorts: "Shape selected moments into editable vertical cuts."
        case .talkingHead: "Tighten pacing, captions, B-roll, and emphasis."
        case .gaming: "Preserve the setup, payoff, and reaction."
        case .appDemo: "Tighten narration and emphasize important interactions."
        case .empty: "Open a normal project and edit however you want."
        }
    }

    var symbol: String {
        switch self {
        case .shorts: "rectangle.portrait.on.rectangle.portrait"
        case .talkingHead: "person.crop.rectangle"
        case .gaming: "gamecontroller"
        case .appDemo: "macwindow"
        case .empty: "plus.rectangle"
        }
    }
}
