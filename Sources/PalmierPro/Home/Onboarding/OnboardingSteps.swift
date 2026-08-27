import SwiftUI

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            OnboardingHeading(
                title: L10n.string("Your video editor, with an AI co-editor."),
                detail: L10n.string("Edit normally, ask AI for a first pass, or work together. The co-editor changes the same project and timeline you can edit yourself.")
            )

            HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
                ForEach(OnboardingMode.allCases) { mode in
                    OnboardingModeCard(mode: mode)
                        .frame(maxWidth: .infinity)
                }
            }

            OnboardingCallout(
                symbol: "arrow.triangle.branch",
                text: L10n.string("Move between Autopilot, Copilot, and Manual editing whenever you want. There is no separate AI project to keep in sync.")
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
                title: L10n.string("Give the co-editor useful context."),
                detail: L10n.string("Palmier can inspect your source media instead of treating editing like a blind text command. Transcripts, source previews, visual search, and audio tools help it work from the footage you actually imported.")
            )

            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.mdLg) {
                OnboardingCapabilityCard(
                    symbol: "waveform",
                    title: L10n.string("Speech"),
                    detail: L10n.string("Transcript and precise spoken timing")
                )
                OnboardingCapabilityCard(
                    symbol: "photo.on.rectangle",
                    title: L10n.string("Visual search"),
                    detail: L10n.string("Find source shots by what is visible")
                )
                OnboardingCapabilityCard(
                    symbol: "film.stack",
                    title: L10n.string("Source inspection"),
                    detail: L10n.string("Preview frames and understand media before cutting")
                )
                OnboardingCapabilityCard(
                    symbol: "metronome",
                    title: L10n.string("Audio"),
                    detail: L10n.string("Beat detection and cleanup tools")
                )
            }

            DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                Text(L10n.string("The Agent can read transcripts, inspect source media, search visuals, and inspect the composited timeline it is editing. GRACE / Film Studio is where additional local runtime and generation capabilities are configured, keeping model plumbing out of the normal editing UI."))
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .padding(.top, AppTheme.Spacing.smMd)
            } label: {
                Label(L10n.string("Learn how it works"), systemImage: "info.circle")
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
            }
            .accessibilityHint(L10n.string("Shows technical details about media context and GRACE."))
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
                detail: L10n.string("Cuts, captions, B-roll, transforms, color, and effects become ordinary editable project state. Change something yourself and the co-editor continues from the timeline you now have.")
            )

            OnboardingTimelineDemo(phase: phase)
                .frame(height: AppTheme.Onboarding.visualHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.string("Timeline demonstration showing an AI edit, a manual adjustment, and the co-editor continuing from the changed project."))

            HStack(spacing: AppTheme.Spacing.smMd) {
                OnboardingPromptChip(text: L10n.string("Keep this through the reaction"))
                OnboardingPromptChip(text: L10n.string("Make the active word yellow"))
                OnboardingPromptChip(text: L10n.string("Use this shot as B-roll"))
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
                detail: L10n.string("When the first cut is wrong, point the co-editor at the exact timeline clip or time range — or @reference the source media — and correct that part without starting over.")
            )

            OnboardingEventStory()

            OnboardingCallout(
                symbol: "scope",
                text: L10n.string("“The jump is the entire point. Keep the payoff and the reaction.”")
            )

            HStack(spacing: AppTheme.Spacing.smMd) {
                OnboardingSelectionToken(symbol: "film", label: L10n.string("Timeline clip"))
                OnboardingSelectionToken(symbol: "clock", label: L10n.string("Time range"))
                OnboardingSelectionToken(symbol: "at", label: L10n.string("Media reference"))
            }
        }
    }
}

struct OnboardingPersonalizationStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
            OnboardingHeading(
                title: L10n.string("Save what keeps working."),
                detail: L10n.string("You do not need to know your editing style on day one. Keep one-off directions in the current project, and save repeatable methods as Skills when they are worth using again.")
            )

            HStack(alignment: .top, spacing: AppTheme.Spacing.mdLg) {
                OnboardingStyleCard(
                    title: L10n.string("My Captions"),
                    symbol: "captions.bubble",
                    details: L10n.string("White · active word yellow · subtle emphasis")
                )
                OnboardingStyleCard(
                    title: L10n.string("Gaming Short"),
                    symbol: "gamecontroller",
                    details: L10n.string("Fast setup · preserve payoff · keep reaction")
                )
                OnboardingStyleCard(
                    title: L10n.string("App Demo"),
                    symbol: "macwindow",
                    details: L10n.string("Clean pacing · clear UI emphasis · minimal B-roll")
                )
            }

            OnboardingCallout(
                symbol: "checklist",
                text: L10n.string("A correction is not silently treated as a permanent rule. Save reusable guidance deliberately when you want the co-editor to use it again.")
            )
        }
    }
}

struct OnboardingComputeStep: View {
    let onOpenSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            OnboardingHeading(
                title: L10n.string("Keep model plumbing out of the editor."),
                detail: L10n.string("Palmier stays focused on the project, timeline, and preview. GRACE / Film Studio owns runtime setup so local generation and heavier capability configuration have one place to live.")
            )

            OnboardingComputeDiagram()
                .frame(height: AppTheme.Onboarding.visualHeight)

            HStack(alignment: .center, spacing: AppTheme.Spacing.mdLg) {
                OnboardingCallout(
                    symbol: "externaldrive",
                    text: L10n.string("Runtime and storage choices belong in GRACE rather than being scattered through editing controls.")
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
                title: L10n.string("Start however you want."),
                detail: L10n.string("Create a normal project, then ask the co-editor for the kind of first pass you need. These are starting ideas, not buttons that lock the project into a mode.")
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
        .frame(
            maxWidth: .infinity,
            minHeight: AppTheme.Onboarding.modeCardMinHeight,
            alignment: .topLeading
        )
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AppTheme.Onboarding.featureCardMinHeight,
            alignment: .topLeading
        )
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
        ("Setup", "person.fill", false),
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
                        .foregroundStyle(
                            event.2 ? AppTheme.Status.successColor : AppTheme.Text.secondaryColor
                        )

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
        .accessibilityLabel(
            L10n.string("Story structure: setup, action, payoff, reaction. Payoff and reaction are marked to keep.")
        )
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
        .frame(
            maxWidth: .infinity,
            minHeight: AppTheme.Onboarding.featureCardMinHeight,
            alignment: .topLeading
        )
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
                symbol: "film",
                title: L10n.string("Palmier"),
                detail: L10n.string("Project · timeline · preview")
            )

            OnboardingDiagramArrow()

            OnboardingComputeNode(
                symbol: "sparkles",
                title: L10n.string("GRACE"),
                detail: L10n.string("Runtime and capability setup")
            )

            OnboardingDiagramArrow()

            OnboardingComputeNode(
                symbol: "cpu",
                title: L10n.string("Configured runtime"),
                detail: L10n.string("Local generation and production tools")
            )
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
        .accessibilityLabel(
            L10n.string("Palmier keeps editing controls separate from the GRACE runtime configuration used for production capabilities.")
        )
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
                .accessibilityHidden(true)

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
        .frame(
            maxWidth: .infinity,
            minHeight: AppTheme.Onboarding.workflowCardMinHeight,
            alignment: .topLeading
        )
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
