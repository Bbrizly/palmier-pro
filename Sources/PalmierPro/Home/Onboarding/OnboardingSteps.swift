import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            OnboardingHeading(
                title: L10n.string("Your video editor, with an AI co-editor."),
                detail: L10n.string("Edit normally, let AI build a first cut, or work together. Everything the AI does stays on the timeline where you can change it.")
            )

            HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
                ForEach(OnboardingMode.allCases) { mode in
                    OnboardingModeCard(mode: mode)
                        .frame(maxWidth: .infinity)
                }
            }

            OnboardingCallout(
                symbol: "arrow.triangle.branch",
                text: L10n.string("Move between Autopilot, Copilot, and Manual editing whenever you want. There is no separate AI project.")
            )
        }
    }
}

struct OnboardingUnderstandingStep: View {
    @State private var showsTechnicalDetails = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
            OnboardingHeading(
                title: L10n.string("It understands your footage."),
                detail: L10n.string("Analyze source media once, then reuse that understanding while you edit instead of making the AI re-watch everything after every change.")
            )

            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.mdLg) {
                OnboardingCapabilityCard(
                    symbol: "waveform",
                    title: L10n.string("Speech"),
                    detail: L10n.string("Transcript and precise spoken timing")
                )
                OnboardingCapabilityCard(
                    symbol: "person.crop.rectangle.stack",
                    title: L10n.string("People"),
                    detail: L10n.string("Subjects, speakers, and tracking")
                )
                OnboardingCapabilityCard(
                    symbol: "rectangle.stack",
                    title: L10n.string("Scenes"),
                    detail: L10n.string("Shots, actions, and visual context")
                )
                OnboardingCapabilityCard(
                    symbol: "waveform.badge.magnifyingglass",
                    title: L10n.string("Audio"),
                    detail: L10n.string("Energy, reactions, and useful events")
                )
            }

            DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                Text(L10n.string("GRACE keeps the editor focused on capabilities instead of model names. Transcription, visual understanding, tracking, and generation can use the Mere runtime you configure, while the analysis can be cached and reused by later edits."))
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .padding(.top, AppTheme.Spacing.smMd)
            } label: {
                Label(L10n.string("Learn how it works"), systemImage: "info.circle")
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
            }
            .accessibilityHint(L10n.string("Shows technical details about GRACE and local analysis."))
        }
    }
}

struct OnboardingSharedTimelineStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
            OnboardingHeading(
                title: L10n.string("AI edits the same timeline you do."),
                detail: L10n.string("Cuts, captions, tracking, B-roll, and effects become ordinary editable project state. Move something yourself and the AI continues from your new timeline.")
            )

            OnboardingTimelineDemo(phase: phase)
                .frame(height: AppTheme.Onboarding.visualHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("Timeline demonstration showing AI edits and a manual adjustment on the same project."))

            HStack(spacing: AppTheme.Spacing.smMd) {
                OnboardingPromptChip(text: L10n.string("Keep this through the reaction"))
                OnboardingPromptChip(text: L10n.string("Track her instead"))
                OnboardingPromptChip(text: L10n.string("Put text behind me"))
            }
        }
        .task {
            if reduceMotion {
                phase = 2
                return
            }
            phase = 0
            try? await Task.sleep(for: .seconds(AppTheme.Anim.pulse))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: AppTheme.Anim.transition)) {
                phase = 1
            }
            try? await Task.sleep(for: .seconds(AppTheme.Anim.pulse))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: AppTheme.Anim.transition)) {
                phase = 2
            }
        }
    }
}

struct OnboardingDirectionStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            OnboardingHeading(
                title: L10n.string("You stay the director."),
                detail: L10n.string("AI can make the first decision. When the story is wrong, point at the exact clip, person, transcript passage, or moment and correct it without starting over.")
            )

            OnboardingEventStory()

            OnboardingCallout(
                symbol: "scope",
                text: L10n.string("“The jump is the entire point. Keep the payoff and the reaction.”")
            )

            HStack(spacing: AppTheme.Spacing.smMd) {
                OnboardingSelectionToken(symbol: "timeline.selection", label: L10n.string("Clip"))
                OnboardingSelectionToken(symbol: "text.quote", label: L10n.string("Transcript"))
                OnboardingSelectionToken(symbol: "person.crop.square", label: L10n.string("Person"))
                OnboardingSelectionToken(symbol: "viewfinder", label: L10n.string("Viewer region"))
                OnboardingSelectionToken(symbol: "clock", label: L10n.string("Time range"))
            }
        }
    }
}

struct OnboardingPersonalizationStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
            OnboardingHeading(
                title: L10n.string("It can become your editor."),
                detail: L10n.string("You do not need to know your style on day one. Save the choices that keep working, and keep one-off corrections local to the edit that needed them.")
            )

            HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
                OnboardingStyleCard(
                    title: L10n.string("My Captions"),
                    symbol: "captions.bubble",
                    details: L10n.string("White · active word yellow · subtle bounce")
                )
                OnboardingStyleCard(
                    title: L10n.string("Gaming Short"),
                    symbol: "gamecontroller",
                    details: L10n.string("Fast setup · never cut payoff · preserve reaction")
                )
                OnboardingStyleCard(
                    title: L10n.string("App Demo"),
                    symbol: "macwindow",
                    details: L10n.string("Clean pacing · UI callouts · minimal B-roll")
                )
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                Text(L10n.string("When you correct something, choose how far that preference should reach:"))
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Text.secondaryColor)

                HStack(spacing: AppTheme.Spacing.smMd) {
                    ForEach(OnboardingPreferenceScope.allCases) { scope in
                        Text(L10n.string(scope.title))
                            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                            .foregroundStyle(AppTheme.Text.primaryColor)
                            .padding(.horizontal, AppTheme.Spacing.mdLg)
                            .frame(height: AppTheme.Onboarding.scopeChipHeight)
                            .background(
                                AppTheme.Interaction.fill(AppTheme.Opacity.faint),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        AppTheme.Border.subtleColor,
                                        lineWidth: AppTheme.BorderWidth.hairline
                                    )
                            }
                    }
                }
            }
        }
    }
}

struct OnboardingComputeStep: View {
    let onOpenSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            OnboardingHeading(
                title: L10n.string("Your editor does not need to become a furnace."),
                detail: L10n.string("Palmier stays focused on the timeline and preview. GRACE owns the production runtime so heavier analysis and generation do not have to become editor UI concerns.")
            )

            OnboardingComputeDiagram()
                .frame(height: AppTheme.Onboarding.visualHeight)

            HStack(alignment: .center, spacing: AppTheme.Spacing.mdLg) {
                OnboardingCallout(
                    symbol: "externaldrive",
                    text: L10n.string("Keep model and media storage where it makes sense for your setup instead of treating the internal SSD as the only place work can live.")
                )

                Button(L10n.string("Open GRACE setup"), action: onOpenSetup)
                    .buttonStyle(.capsule(
                        .secondary,
                        size: .regular,
                        fill: AnyShapeStyle(AppTheme.Onboarding.secondaryButtonFill)
                    ))
                    .accessibilityHint(L10n.string("Opens the real Film Studio setup window."))
            }
        }
    }
}

struct OnboardingWorkflowsStep: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
            OnboardingHeading(
                title: L10n.string("What do you want to make?"),
                detail: L10n.string("These are editing intents, not locked modes. Start a normal project, then let the co-editor take as much or as little of the first pass as you want.")
            )

            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.mdLg) {
                ForEach(OnboardingWorkflow.allCases) { workflow in
                    OnboardingWorkflowCard(workflow: workflow)
                }
            }

            OnboardingCallout(
                symbol: "arrow.left.and.right",
                text: L10n.string("Autopilot, Copilot, and Manual editing can all happen inside the same project.")
            )
        }
    }
}

private struct OnboardingHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.title2, weight: AppTheme.FontWeight.light))
                .tracking(AppTheme.Tracking.tight)
                .foregroundStyle(AppTheme.Text.primaryColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: AppTheme.FontSize.mdLg))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingModeCard: View {
    let mode: OnboardingMode

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Image(systemName: mode.symbol)
                .font(.system(size: AppTheme.IconSize.lg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .accessibilityHidden(true)
            Text(L10n.string(mode.title))
                .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(L10n.string(mode.detail))
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Onboarding.modeCardMinHeight, alignment: .topLeading)
        .padding(AppTheme.Spacing.lgXl)
        .background(
            AppTheme.Background.raisedColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
    }
}

private struct OnboardingCapabilityCard: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
            Image(systemName: symbol)
                .font(.system(size: AppTheme.IconSize.md, weight: AppTheme.FontWeight.medium))
                .frame(width: AppTheme.IconSize.lgXl)
                .foregroundStyle(AppTheme.Text.primaryColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(detail)
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Onboarding.featureCardMinHeight, alignment: .topLeading)
        .padding(AppTheme.Spacing.lg)
        .background(
            AppTheme.Background.raisedColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
    }
}

private struct OnboardingTimelineDemo: View {
    let phase: Int

    var body: some View {
        VStack(spacing: AppTheme.Spacing.zero) {
            HStack(spacing: AppTheme.Spacing.smMd) {
                Label(L10n.string("Same project"), systemImage: "film.stack")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Spacer()
                statusLabel
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)

            Divider().overlay(AppTheme.Border.subtleColor)

            timelineTrack(
                label: L10n.string("Video"),
                symbol: "film",
                clips: [L10n.string("Setup"), L10n.string("Payoff"), L10n.string("Reaction")]
            )
            timelineTrack(
                label: L10n.string("Text"),
                symbol: "textformat",
                clips: [L10n.string("Captions"), L10n.string("Emphasis"), L10n.string("Outro")]
            )
            timelineTrack(
                label: L10n.string("Audio"),
                symbol: "waveform",
                clips: [L10n.string("Voice"), L10n.string("Voice"), L10n.string("Reaction")]
            )
        }
        .background(
            AppTheme.Background.surfaceColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
                .strokeBorder(AppTheme.Border.primaryColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if phase == 0 {
            Label(L10n.string("AI building first cut"), systemImage: "sparkles")
                .foregroundStyle(AppTheme.Accent.timecodeColor)
        } else if phase == 1 {
            Label(L10n.string("You adjusted the payoff"), systemImage: "cursorarrow")
                .foregroundStyle(AppTheme.Status.successColor)
        } else {
            Label(L10n.string("AI continues from your edit"), systemImage: "arrow.triangle.branch")
                .foregroundStyle(AppTheme.Status.successColor)
        }
    }

    private func timelineTrack(label: String, symbol: String, clips: [String]) -> some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            Label(label, systemImage: symbol)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .frame(width: AppTheme.Onboarding.timelineLabelWidth, alignment: .leading)

            ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                Text(clip)
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.Onboarding.timelineClipHeight)
                    .background(
                        clipFill(index: index),
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .strokeBorder(
                                clipBorder(index: index),
                                lineWidth: AppTheme.BorderWidth.hairline
                            )
                    }
                    .offset(x: clipOffset(index: index))
            }
        }
        .frame(height: AppTheme.Onboarding.timelineTrackHeight)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func clipFill(index: Int) -> Color {
        if phase >= 1, index == 1 {
            return AppTheme.Status.successColor.opacity(AppTheme.Opacity.muted)
        }
        return AppTheme.Interaction.fill(AppTheme.Opacity.faint)
    }

    private func clipBorder(index: Int) -> Color {
        if phase >= 1, index == 1 {
            return AppTheme.Status.successColor.opacity(AppTheme.Opacity.high)
        }
        return AppTheme.Border.subtleColor
    }

    private func clipOffset(index: Int) -> CGFloat {
        guard phase == 1, index == 1 else { return AppTheme.Spacing.zero }
        return AppTheme.Spacing.smMd
    }
}

private struct OnboardingEventStory: View {
    private let events = [
        ("Setup", "person.fill.questionmark", false),
        ("Action", "figure.run", false),
        ("Payoff", "sparkles", true),
        ("Reaction", "face.smiling", true),
    ]

    var body: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                VStack(spacing: AppTheme.Spacing.smMd) {
                    Image(systemName: event.1)
                        .font(.system(size: AppTheme.IconSize.mdLg, weight: AppTheme.FontWeight.medium))
                        .foregroundStyle(event.2 ? AppTheme.Status.successColor : AppTheme.Text.secondaryColor)
                    Text(L10n.string(event.0))
                        .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    if event.2 {
                        Label(L10n.string("Keep"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Status.successColor)
                    } else {
                        Text(L10n.string("Context"))
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.lgXl)
                .background(
                    event.2
                        ? AppTheme.Status.successColor.opacity(AppTheme.Opacity.faint)
                        : AppTheme.Background.raisedColor,
                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .strokeBorder(
                            event.2
                                ? AppTheme.Status.successColor.opacity(AppTheme.Opacity.medium)
                                : AppTheme.Border.subtleColor,
                            lineWidth: AppTheme.BorderWidth.hairline
                        )
                }

                if index < events.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: AppTheme.IconSize.xs, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.mutedColor)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("Story structure: setup, action, payoff, reaction. Payoff and reaction are marked to keep."))
    }
}

private struct OnboardingSelectionToken: View {
    let symbol: String
    let label: String

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(AppTheme.Text.secondaryColor)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(AppTheme.Interaction.fill(AppTheme.Opacity.faint), in: Capsule())
    }
}

private struct OnboardingStyleCard: View {
    let title: String
    let symbol: String
    let details: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Label(title, systemImage: symbol)
                .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(details)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Onboarding.featureCardMinHeight, alignment: .topLeading)
        .padding(AppTheme.Spacing.lg)
        .background(
            AppTheme.Background.raisedColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
    }
}

private struct OnboardingComputeDiagram: View {
    var body: some View {
        HStack(spacing: AppTheme.Spacing.lgXl) {
            OnboardingComputeNode(
                symbol: "timeline.selection",
                title: L10n.string("Palmier"),
                detail: L10n.string("Timeline · preview · manual edits")
            )

            OnboardingDiagramArrow()

            OnboardingComputeNode(
                symbol: "sparkles",
                title: L10n.string("GRACE"),
                detail: L10n.string("Plans and routes production work")
            )

            OnboardingDiagramArrow()

            VStack(spacing: AppTheme.Spacing.smMd) {
                OnboardingComputeNode(
                    symbol: "laptopcomputer",
                    title: L10n.string("This Mac"),
                    detail: L10n.string("Lightweight or available work")
                )
                OnboardingComputeNode(
                    symbol: "network",
                    title: L10n.string("Other compute"),
                    detail: L10n.string("Heavy jobs when configured")
                )
            }
        }
        .padding(AppTheme.Spacing.lgXl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            AppTheme.Background.surfaceColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.string("Palmier sends production work through GRACE to this Mac or other configured compute."))
    }
}

private struct OnboardingComputeNode: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: AppTheme.Spacing.smMd) {
            Image(systemName: symbol)
                .font(.system(size: AppTheme.IconSize.lg, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(title)
                .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)
            Text(detail)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: AppTheme.Onboarding.diagramNodeWidth)
        .padding(.vertical, AppTheme.Spacing.lg)
        .padding(.horizontal, AppTheme.Spacing.md)
        .background(
            AppTheme.Background.raisedColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }
}

private struct OnboardingDiagramArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: AppTheme.IconSize.smMd, weight: AppTheme.FontWeight.medium))
            .foregroundStyle(AppTheme.Text.mutedColor)
            .accessibilityHidden(true)
    }
}

private struct OnboardingWorkflowCard: View {
    let workflow: OnboardingWorkflow

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
            Image(systemName: workflow.symbol)
                .font(.system(size: AppTheme.IconSize.md, weight: AppTheme.FontWeight.medium))
                .frame(width: AppTheme.IconSize.lgXl)
                .foregroundStyle(AppTheme.Text.primaryColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(L10n.string(workflow.title))
                    .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(L10n.string(workflow.detail))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.Onboarding.workflowCardMinHeight, alignment: .topLeading)
        .padding(AppTheme.Spacing.lg)
        .background(
            AppTheme.Background.raisedColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.hairline)
        }
    }
}

private struct OnboardingCallout: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            Image(systemName: symbol)
                .frame(width: AppTheme.IconSize.smMd)
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.mdLg)
        .background(
            AppTheme.Interaction.fill(AppTheme.Opacity.faint),
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
        )
    }
}

private struct OnboardingPromptChip: View {
    let text: String

    var body: some View {
        Text("“\(text)”")
            .font(.system(size: AppTheme.FontSize.sm))
            .foregroundStyle(AppTheme.Text.secondaryColor)
            .lineLimit(1)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(AppTheme.Interaction.fill(AppTheme.Opacity.faint), in: Capsule())
    }
}
