import SwiftUI

struct OnboardingOverlay: View {
    @Bindable var onboarding: OnboardingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let scrollTopID = "onboarding-scroll-top"

    var body: some View {
        ZStack {
            AppTheme.MediaOverlay.backgroundColor.opacity(AppTheme.Opacity.strong)
                .ignoresSafeArea()

            card
                .frame(
                    width: AppTheme.Onboarding.cardWidth,
                    height: AppTheme.Onboarding.cardHeight
                )
                .padding(AppTheme.Spacing.xl)
        }
        .transition(.opacity)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: AppTheme.Anim.transition),
            value: onboarding.step
        )
        .onExitCommand(perform: onboarding.skip)
    }

    private var card: some View {
        VStack(spacing: AppTheme.Spacing.zero) {
            header
            Divider()
                .overlay(AppTheme.Border.subtleColor)
            content
            Divider()
                .overlay(AppTheme.Border.subtleColor)
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                        .strokeBorder(
                            AppTheme.Border.primaryColor,
                            lineWidth: AppTheme.BorderWidth.hairline
                        )
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .shadow(AppTheme.Shadow.lg)
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.mdLg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(L10n.string("Getting Started"))
                    .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(L10n.string("Step \(onboarding.step.position) of \(OnboardingStep.count)"))
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            ProgressView(value: onboarding.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(L10n.string("Onboarding progress"))
                .accessibilityValue(
                    L10n.string("Step \(onboarding.step.position) of \(OnboardingStep.count)")
                )

            Button(L10n.string("Skip tutorial"), action: onboarding.skip)
                .buttonStyle(.plain)
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .accessibilityHint(L10n.string("Closes the tutorial and returns to Home."))
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.vertical, AppTheme.Spacing.lgXl)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear
                    .frame(height: 1)
                    .id(Self.scrollTopID)

                Group {
                    switch onboarding.step {
                    case .welcome:
                        OnboardingWelcomeStep()
                    case .understanding:
                        OnboardingUnderstandingStep()
                    case .sharedTimeline:
                        OnboardingSharedTimelineStep()
                    case .direction:
                        OnboardingDirectionStep()
                    case .personalization:
                        OnboardingPersonalizationStep()
                    case .compute:
                        OnboardingComputeStep(onOpenSetup: onboarding.openComputeSetup)
                    case .workflows:
                        OnboardingWorkflowsStep()
                    }
                }
                .id(onboarding.step)
                .frame(maxWidth: AppTheme.Onboarding.contentMaxWidth, alignment: .topLeading)
                .padding(.horizontal, AppTheme.Spacing.xxl)
                .padding(.vertical, AppTheme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .top)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                )
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: onboarding.step) { _, _ in
                proxy.scrollTo(Self.scrollTopID, anchor: .top)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            if onboarding.canGoBack {
                Button(L10n.string("Back"), action: onboarding.goBack)
                    .buttonStyle(.capsule(
                        .secondary,
                        size: .regular,
                        fill: AnyShapeStyle(AppTheme.Onboarding.secondaryButtonFill)
                    ))
            }

            Spacer()

            if onboarding.isLastStep {
                Button(L10n.string("Start editing"), action: onboarding.finishAndCreateProject)
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.string("Continue"), action: onboarding.advance)
                    .buttonStyle(.capsule(.prominent, size: .regular))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xxl)
        .padding(.vertical, AppTheme.Spacing.lgXl)
    }
}
