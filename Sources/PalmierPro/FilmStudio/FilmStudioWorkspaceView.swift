import FilmStudioCore
import Foundation
import SwiftUI

@MainActor
struct FilmStudioWorkspaceView: View {
    enum Section: String, CaseIterable, Identifiable {
        case studio
        case development
        case shots
        case review
        case delivery
        case setup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .studio: "Studio"
            case .development: "Development"
            case .shots: "Shots"
            case .review: "Review"
            case .delivery: "Delivery"
            case .setup: "Setup"
            }
        }

        var symbol: String {
            switch self {
            case .studio: "square.grid.2x2"
            case .development: "text.book.closed"
            case .shots: "rectangle.stack.badge.play"
            case .review: "checkmark.seal"
            case .delivery: "shippingbox"
            case .setup: "wrench.and.screwdriver"
            }
        }
    }

    @ObservedObject var model: PalmierFilmStudioModel
    let bridge: FilmStudioPalmierBridge

    @State private var section: Section = .studio
    @State private var showingNewFilm = false
    @State private var showingBrief = false
    @State private var showingProductionSettings = false
    @State private var showingHumanReview = false
    @State private var rerollShot: FilmProductionShot?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.zero) {
            sidebar
                .frame(width: AppTheme.Settings.sidebarWidth)
            divider(width: AppTheme.BorderWidth.hairline)
            VStack(spacing: AppTheme.Spacing.zero) {
                header
                divider(height: AppTheme.BorderWidth.hairline)
                messageArea
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                divider(height: AppTheme.BorderWidth.hairline)
                actionBar
            }
        }
        .background(AppTheme.Background.baseColor)
        .sheet(isPresented: $showingNewFilm) { NewFilmSheet(model: model) }
        .sheet(isPresented: $showingBrief) { CompleteBriefSheet(model: model) }
        .sheet(isPresented: $showingProductionSettings) { ProductionSettingsSheet(model: model) }
        .sheet(isPresented: $showingHumanReview) { HumanReviewSheet(model: model) }
        .sheet(item: $rerollShot) { shot in RerollShotSheet(model: model, shot: shot) }
    }

    private var creativeRevisionRequired: Bool {
        model.snapshot?.project.issues.contains {
            $0.code == "creative-review" && $0.blocking
        } == true
    }

    private var technicalRevisionRequired: Bool {
        model.snapshot?.project.issues.contains {
            $0.code == "technical-review" && $0.blocking
        } == true
    }

    private var revisionRequired: Bool {
        model.hasPendingReviewRequests || creativeRevisionRequired || technicalRevisionRequired
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.zero) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Film Studio")
                    .font(.system(size: AppTheme.FontSize.lg, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: "GRACE production")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            .padding(.horizontal, AppTheme.Spacing.lgXl)
            .padding(.top, AppTheme.Spacing.xlXxl)
            .padding(.bottom, AppTheme.Spacing.mdLg)

            VStack(spacing: AppTheme.Spacing.xxs) {
                ForEach(Section.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            Image(systemName: item.symbol)
                                .frame(width: AppTheme.IconSize.smMd)
                            Text(verbatim: item.title)
                                .font(.system(size: AppTheme.FontSize.md))
                            Spacer(minLength: AppTheme.Spacing.zero)
                            if item == .setup, !model.productionReady {
                                Circle()
                                    .fill(AppTheme.Status.warningColor)
                                    .frame(width: AppTheme.Spacing.sm, height: AppTheme.Spacing.sm)
                                    .accessibilityLabel(Text(verbatim: "Setup incomplete"))
                            }
                        }
                        .foregroundStyle(
                            section == item ? AppTheme.Text.primaryColor : AppTheme.Text.secondaryColor
                        )
                        .padding(.horizontal, AppTheme.Spacing.mdLg)
                        .padding(.vertical, AppTheme.Spacing.smMd)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            section == item
                                ? AppTheme.Interaction.fill(AppTheme.Opacity.muted)
                                : AppTheme.Background.clearColor,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.smMd)

            Spacer(minLength: AppTheme.Spacing.lg)

            if let project = model.snapshot?.project {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(verbatim: project.title)
                        .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .lineLimit(2)
                    Text(verbatim: "\(model.displayName(project.phase)) · \(model.displayName(project.status))")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    FilmStudioButton("Close Film") { model.closeProject() }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .disabled(model.isBusy)
                }
                .padding(AppTheme.Spacing.lgXl)
            }
        }
        .background(AppTheme.Background.surfaceColor.opacity(AppTheme.Opacity.medium))
    }

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.mdLg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(verbatim: section.title)
                    .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.regular))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: headerSubtitle)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .lineLimit(1)
            }
            Spacer(minLength: AppTheme.Spacing.lg)
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(verbatim: model.activity)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            FilmStudioButton("Open Film…") { model.chooseProject() }
                .disabled(model.isBusy)
            FilmStudioButton("New Film") {
                if model.planningReady {
                    showingNewFilm = true
                } else {
                    section = .setup
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.mdLg)
        .background(AppTheme.Background.baseColor.opacity(AppTheme.Opacity.prominent))
    }

    private var headerSubtitle: String {
        if let project = model.snapshot?.project {
            return "\(project.title) · \(model.displayName(project.phase))"
        }
        if model.productionReady { return "Local production is ready" }
        if model.agentReady { return "Story production is ready; finish media setup before rendering" }
        if model.planningReady { return "Planning is ready; finish producer setup before advancing" }
        return "Open an existing film or install the planning tools to start one"
    }

    @ViewBuilder
    private var messageArea: some View {
        if let error = model.errorMessage {
            messageBanner(error, symbol: "exclamationmark.triangle.fill", color: AppTheme.Status.errorColor)
        } else if let notice = model.noticeMessage {
            messageBanner(notice, symbol: "checkmark.circle.fill", color: AppTheme.Status.successColor)
        }
    }

    private func messageBanner(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(verbatim: text)
                .font(.system(size: AppTheme.FontSize.smMd))
                .foregroundStyle(AppTheme.Text.primaryColor)
                .textSelection(.enabled)
            Spacer(minLength: AppTheme.Spacing.md)
            Button {
                model.dismissMessages()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .background(color.opacity(AppTheme.Opacity.faint))
    }

    @ViewBuilder
    private var detail: some View {
        if section == .setup {
            setupView
        } else if let snapshot = model.snapshot {
            switch section {
            case .studio: studioView(snapshot)
            case .development: developmentView(snapshot)
            case .shots: shotsView(snapshot)
            case .review: reviewView(snapshot)
            case .delivery: deliveryView(snapshot)
            case .setup: EmptyView()
            }
        } else {
            emptyProjectView
        }
    }

    private var emptyProjectView: some View {
        VStack(spacing: AppTheme.Spacing.lgXl) {
            Image(systemName: "movieclapper")
                .font(.system(size: AppTheme.FontSize.display, weight: AppTheme.FontWeight.light))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            VStack(spacing: AppTheme.Spacing.smMd) {
                Text(verbatim: "No film open")
                    .font(.system(size: AppTheme.FontSize.xl, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: model.planningReady
                    ? "Start with an idea. Additional local setup is requested only when the next production step needs it."
                    : "Open any GRACE run.json to inspect it. New films only need mere.run and Film Studio tools to begin planning.")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: AppTheme.Spacing.smMd) {
                FilmStudioButton("Open Film…") { model.chooseProject() }
                FilmStudioButton(model.planningReady ? "New Film" : "Finish Setup") {
                    if model.planningReady { showingNewFilm = true } else { section = .setup }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: AppTheme.Settings.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.xxl)
    }

    private func studioView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
                if !model.productionReady {
                    Button {
                        section = .setup
                    } label: {
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundStyle(AppTheme.Status.warningColor)
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                Text(verbatim: "Some Film Studio setup is incomplete")
                                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                                Text(verbatim: "Only the step that needs the missing component is blocked.")
                                    .font(.system(size: AppTheme.FontSize.sm))
                                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                            }
                            Spacer(minLength: AppTheme.Spacing.md)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(AppTheme.Text.tertiaryColor)
                        }
                        .padding(AppTheme.Spacing.mdLg)
                        .background(
                            AppTheme.Status.warningColor.opacity(AppTheme.Opacity.faint),
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: AppTheme.Spacing.mdLg) {
                    metric("Phase", model.displayName(snapshot.project.phase), "arrow.triangle.2.circlepath")
                    metric("Shots", String(snapshot.project.shots.count), "rectangle.stack")
                    metric("Checks", "\(snapshot.project.proof.completedCount)/10", "checkmark.seal")
                    metric(
                        "Blocking",
                        String(snapshot.project.issues.filter(\.blocking).count),
                        "exclamationmark.triangle"
                    )
                }

                FilmStudioCard(title: "Production proof") {
                    ProgressView(value: Double(snapshot.project.proof.completedCount), total: 10)
                    Text(verbatim: "\(snapshot.project.proof.completedCount) of 10 delivery checks complete")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }

                FilmStudioCard(title: "Departments") {
                    if snapshot.project.departments.isEmpty {
                        Text(verbatim: "Departments appear after the brief is approved.")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    } else {
                        ForEach(snapshot.project.departments) { department in
                            HStack(spacing: AppTheme.Spacing.smMd) {
                                Image(systemName: statusSymbol(department.status))
                                    .foregroundStyle(statusColor(department.status))
                                    .frame(width: AppTheme.IconSize.smMd)
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                    Text(verbatim: model.displayName(department.role))
                                    Text(verbatim: model.displayName(department.phase))
                                        .font(.system(size: AppTheme.FontSize.sm))
                                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                                }
                                Spacer(minLength: AppTheme.Spacing.md)
                                Text(verbatim: model.displayName(department.status))
                                    .font(.system(size: AppTheme.FontSize.sm))
                                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                            }
                            .padding(.vertical, AppTheme.Spacing.smMd)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }

    private func developmentView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
                if model.briefNeedsInput {
                    FilmStudioCard(title: "Brief needs your input") {
                        ForEach(snapshot.project.brief.openQuestions, id: \.self) { question in
                            FilmStudioLabel(question, systemImage: "questionmark.circle")
                                .foregroundStyle(AppTheme.Text.secondaryColor)
                        }
                        FilmStudioButton("Complete Brief…") { showingBrief = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                    }
                }

                FilmStudioCard(title: "Creative brief") {
                    optionalField("Audience", snapshot.project.brief.audience)
                    optionalField("Genre", snapshot.project.brief.genre)
                    optionalField("Tone", snapshot.project.brief.tone)
                    optionalField("Rating", snapshot.project.brief.rating)
                    optionalField("Intended use", snapshot.project.brief.usage)
                    if !snapshot.project.brief.references.isEmpty {
                        field("References", snapshot.project.brief.references.joined(separator: "\n"))
                    }
                }

                if let treatment = snapshot.treatment {
                    FilmStudioCard(title: "Treatment") {
                        field("Logline", treatment.logline)
                        field("Synopsis", treatment.synopsis)
                        field("Theme", treatment.theme)
                        field("Visual language", treatment.visualLanguage)
                        field("Sound language", treatment.soundLanguage)
                    }
                    FilmStudioCard(title: "Story beats") {
                        ForEach(Array(treatment.beats.enumerated()), id: \.offset) { index, beat in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                                Text(verbatim: String(index + 1))
                                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                                Text(verbatim: beat)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    FilmStudioCard(title: "Treatment") {
                        Text(verbatim: "Approve the brief and continue production to build the treatment.")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                }

                if snapshot.productionPlan != nil {
                    FilmStudioCard(title: "Production execution") {
                        valueRow("Mode", model.displayName(snapshot.project.production.mode))
                        valueRow("Takes per shot", String(snapshot.project.production.takesPerShot))
                        if model.pendingGate == "production" {
                            if model.productionNeedsConfiguration {
                                FilmStudioButton("Configure & Check Models…") {
                                    showingProductionSettings = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isBusy || model.runtime?.filmToolsReady != true)
                            } else {
                                FilmStudioButton("Change Production Settings…") {
                                    showingProductionSettings = true
                                }
                                .disabled(model.isBusy || model.runtime?.filmToolsReady != true)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }

    private func shotsView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                if let shots = snapshot.productionPlan?.shots, !shots.isEmpty {
                    ForEach(shots) { shot in
                        let state = snapshot.project.shots.first { $0.id == shot.id }
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.smMd) {
                                Text(verbatim: shot.id)
                                    .font(.system(
                                        size: AppTheme.FontSize.sm,
                                        weight: AppTheme.FontWeight.semibold,
                                        design: .monospaced
                                    ))
                                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                                Text(verbatim: shot.purpose)
                                    .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.medium))
                                    .lineLimit(2)
                                Spacer(minLength: AppTheme.Spacing.md)
                                Text(verbatim: model.displayName(state?.status ?? shot.status))
                                    .font(.system(size: AppTheme.FontSize.sm))
                                    .foregroundStyle(statusColor(state?.status ?? shot.status))
                            }
                            Text(verbatim: shot.prompt)
                                .font(.system(size: AppTheme.FontSize.md))
                                .foregroundStyle(AppTheme.Text.secondaryColor)
                                .lineLimit(4)
                            HStack(spacing: AppTheme.Spacing.lg) {
                                FilmStudioLabel(String(format: "%.1fs", shot.durationSeconds), systemImage: "clock")
                                FilmStudioLabel("Take \(state?.take ?? shot.take)", systemImage: "film.stack")
                                if !shot.characters.isEmpty {
                                    FilmStudioLabel(shot.characters.joined(separator: ", "), systemImage: "person.2")
                                        .lineLimit(1)
                                }
                                Spacer(minLength: AppTheme.Spacing.md)
                                if state?.take != nil {
                                    FilmStudioButton("Reroll…") { rerollShot = shot }
                                        .disabled(!model.canReroll)
                                }
                            }
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                        }
                        .padding(AppTheme.Spacing.mdLg)
                        .background(
                            AppTheme.Background.raisedColor,
                            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        )
                    }
                } else {
                    FilmStudioCard(title: "No shot plan yet") {
                        Text(verbatim: "Approve development and continue production to build the shot list.")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }

    private func reviewView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
                if model.playableCutURL != nil {
                    FilmStudioCard(title: "Current cut") {
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            FilmStudioButton("Play Cut") { model.openPlayableCut() }
                            if !snapshot.project.proof.review && !revisionRequired {
                                Text(verbatim: "Continue Production runs technical and independent review.")
                                    .font(.system(size: AppTheme.FontSize.sm))
                                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                            }
                        }
                    }
                }

                if creativeRevisionRequired || snapshot.project.proof.review {
                    FilmStudioCreativeReviewPanel(
                        model: model,
                        runManifest: snapshot.runManifest,
                        projectUpdatedAt: snapshot.project.updatedAt
                    )
                }

                if technicalRevisionRequired {
                    FilmStudioCard(title: "Technical revision required") {
                        Text(verbatim: "The current rough cut failed a technical delivery check. Review the blocking issue below before rebuilding the affected media or cut.")
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                    }
                }

                if model.needsHumanReviewDecision {
                    FilmStudioCard(title: "Your review") {
                        Text(verbatim: "Watch the current cut, then approve this exact version for picture lock or request specific shot revisions.")
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                        FilmStudioButton("Review & Decide…") { showingHumanReview = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                    }
                } else if snapshot.project.proof.humanReview {
                    FilmStudioCard(title: "Your review") {
                        FilmStudioLabel(
                            "Human review is recorded against this exact cut.",
                            systemImage: "checkmark.seal.fill"
                        )
                        .foregroundStyle(AppTheme.Status.successColor)
                    }
                }

                FilmStudioCard(title: "Issues") {
                    if snapshot.project.issues.isEmpty {
                        FilmStudioLabel("No recorded issues", systemImage: "checkmark.circle")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    } else {
                        ForEach(snapshot.project.issues) { issue in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                                Image(systemName: issue.blocking
                                    ? "exclamationmark.octagon.fill"
                                    : "exclamationmark.triangle")
                                    .foregroundStyle(issue.blocking
                                        ? AppTheme.Status.errorColor
                                        : AppTheme.Status.warningColor)
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                    Text(verbatim: issue.code)
                                        .font(.system(
                                            size: AppTheme.FontSize.sm,
                                            weight: AppTheme.FontWeight.semibold,
                                            design: .monospaced
                                        ))
                                    Text(verbatim: issue.message)
                                        .foregroundStyle(AppTheme.Text.secondaryColor)
                                }
                                Spacer(minLength: AppTheme.Spacing.md)
                                if issue.blocking {
                                    Text(verbatim: "Blocking")
                                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                                        .foregroundStyle(AppTheme.Status.errorColor)
                                }
                            }
                            .padding(.vertical, AppTheme.Spacing.smMd)
                        }
                    }
                }

                FilmStudioCard(title: "Human review rerolls") {
                    if snapshot.project.reviewRequests.isEmpty {
                        Text(verbatim: "No human review reroll requests.")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    } else {
                        ForEach(snapshot.project.reviewRequests) { request in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    HStack(spacing: AppTheme.Spacing.smMd) {
                                        Text(verbatim: request.shotId)
                                            .font(.system(
                                                size: AppTheme.FontSize.sm,
                                                weight: AppTheme.FontWeight.semibold,
                                                design: .monospaced
                                            ))
                                        Text(verbatim: model.displayName(request.status))
                                            .font(.system(size: AppTheme.FontSize.sm))
                                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                                    }
                                    Text(verbatim: request.note)
                                        .foregroundStyle(AppTheme.Text.secondaryColor)
                                }
                                Spacer(minLength: AppTheme.Spacing.md)
                                if request.status == "pending" {
                                    FilmStudioButton("Prepare Reroll") {
                                        model.reroll(shotID: request.shotId, note: request.note)
                                    }
                                    .disabled(!model.canReroll)
                                }
                            }
                            .padding(.vertical, AppTheme.Spacing.smMd)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }

    private func deliveryView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
                FilmStudioCard(title: "Palmier handoff") {
                    if let cutURL = model.playableCutURL {
                        FilmStudioLabel(cutURL.lastPathComponent, systemImage: "film")
                            .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.medium))
                        Text(verbatim: cutURL.path)
                            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            FilmStudioButton("Import Cut into Palmier") {
                                bridge.importPlayableCut(using: model)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isBusy)
                            FilmStudioButton("Play Cut") { model.openPlayableCut() }
                            FilmStudioButton("Reveal in Finder") { model.revealPlayableCut() }
                        }
                        Text(verbatim: "Import uses Palmier's normal media pipeline and the currently active Palmier project.")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    } else {
                        Text(verbatim: "No playable cut exists yet. The newest verified cut appears here automatically.")
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }
                }

                FilmStudioCard(title: "Delivery checks") {
                    proof("Creation", snapshot.project.proof.creation)
                    proof("Selected clips", snapshot.project.proof.clips)
                    proof("Assembly", snapshot.project.proof.assembly)
                    proof("Dialogue", snapshot.project.proof.dialogue)
                    proof("Sound", snapshot.project.proof.sound)
                    proof("Captions", snapshot.project.proof.captions)
                    proof("Inspection", snapshot.project.proof.inspection)
                    proof("Independent review", snapshot.project.proof.review)
                    proof("Human review", snapshot.project.proof.humanReview)
                    proof("Delivery", snapshot.project.proof.delivery)
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lgXl) {
                FilmStudioCard(title: setupTitle) {
                    Text(verbatim: setupSummary)
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    if model.isRuntimeRefreshing {
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            ProgressView().controlSize(.small)
                            Text(verbatim: "Checking local runtime…")
                                .font(.system(size: AppTheme.FontSize.sm))
                                .foregroundStyle(AppTheme.Text.tertiaryColor)
                        }
                    }
                }

                if let runtime = model.runtime {
                    FilmStudioCard(title: "Requirements") {
                        setupRow(
                            title: "mere.run",
                            detail: runtime.mereRunPath ?? runtime.mereRunError ?? "Not installed",
                            ready: runtime.mereRunReady,
                            actionTitle: runtime.mereRunReady ? nil : "Download",
                            action: runtime.mereRunReady ? nil : model.openMereDownloads
                        )
                        setupRow(
                            title: "Film Studio tools",
                            detail: runtime.filmToolPath ?? runtime.filmToolError ?? "Not installed",
                            ready: runtime.filmToolsReady,
                            actionTitle: !runtime.filmToolsReady && runtime.mereRunReady ? "Install" : nil,
                            action: !runtime.filmToolsReady && runtime.mereRunReady ? model.installFilmTools : nil
                        )
                        setupRow(
                            title: "Pi producer",
                            detail: runtime.agentStatus?.pi.path
                                ?? runtime.doctor?.check(named: "pi")?.detail
                                ?? "Not installed",
                            ready: runtime.piReady,
                            actionTitle: !runtime.piReady && runtime.mereRunReady ? "Install" : nil,
                            action: !runtime.piReady && runtime.mereRunReady ? model.installPi : nil
                        )
                        setupRow(
                            title: "Local producer model",
                            detail: agentModelDetail(runtime),
                            ready: runtime.agentModelReady,
                            actionTitle: !runtime.agentModelReady && runtime.mereRunReady
                                ? "Copy Setup Command"
                                : nil,
                            action: !runtime.agentModelReady && runtime.mereRunReady
                                ? model.copyModelSetupCommand
                                : nil
                        )
                        setupRow(
                            title: "Pi mere-run provider",
                            detail: providerDetail(runtime),
                            ready: runtime.providerReady,
                            actionTitle: runtime.agentModelReady && !runtime.providerReady ? "Configure" : nil,
                            action: runtime.agentModelReady && !runtime.providerReady ? model.configurePiProvider : nil
                        )
                        setupRow(
                            title: "FFmpeg",
                            detail: runtime.doctor?.check(named: "ffmpeg")?.detail
                                ?? "Waiting for Film Studio tools",
                            ready: runtime.ffmpegReady,
                            actionTitle: runtime.filmToolsReady && !runtime.mediaToolsReady
                                ? "Copy Install Command"
                                : nil,
                            action: runtime.filmToolsReady && !runtime.mediaToolsReady
                                ? model.copyFFmpegInstallCommand
                                : nil
                        )
                        setupRow(
                            title: "FFprobe",
                            detail: runtime.doctor?.check(named: "ffprobe")?.detail
                                ?? "Waiting for Film Studio tools",
                            ready: runtime.ffprobeReady
                        )
                    }

                    FilmStudioCard(title: "Local producer server") {
                        Text(verbatim: "Producer steps reuse a healthy configured loopback mere.run server. Otherwise Palmier starts the selected local model and stops that owned process when Palmier exits.")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                    }

                    if let error = runtime.agentError ?? runtime.doctorError {
                        FilmStudioCard(title: "Runtime detail") {
                            Text(verbatim: error)
                                .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                                .foregroundStyle(AppTheme.Text.tertiaryColor)
                                .textSelection(.enabled)
                        }
                    }
                }

                FilmStudioCard(title: "Advanced") {
                    FilmStudioDisclosureGroup("Executable overrides") {
                        executableOverride("mere.run", text: $model.mereRunOverride)
                        executableOverride("mere-film-tools", text: $model.filmToolOverride)
                        HStack(spacing: AppTheme.Spacing.smMd) {
                            FilmStudioButton("Recheck") {
                                Task { @MainActor in await model.refreshRuntime() }
                            }
                            .disabled(model.isRuntimeRefreshing || model.isBusy)
                            FilmStudioButton("Use Automatic Paths") { model.resetExecutableOverrides() }
                                .disabled(model.isBusy)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
    }

    private var setupTitle: String {
        if model.productionReady { return "Production ready" }
        if model.agentReady { return "Finish media setup" }
        if model.planningReady { return "Finish producer setup" }
        return "Install planning tools"
    }

    private var setupSummary: String {
        if model.productionReady {
            return "GRACE can plan, produce, render, review, and deliver films on this Mac."
        }
        if model.agentReady {
            return "Planning and story production are ready. Install the remaining media tools before rendering."
        }
        if model.planningReady {
            return "You can create and complete a film brief now. Pi, a local model, and its provider are required when story production begins."
        }
        return "Install mere.run and Film Studio tools to create new films. Existing GRACE workspaces can still be inspected."
    }

    private var actionBar: some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            if model.briefNeedsInput {
                FilmStudioButton("Complete Brief…") { showingBrief = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            } else if model.productionNeedsConfiguration {
                FilmStudioButton("Configure Production…") { showingProductionSettings = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.runtime?.filmToolsReady != true)
            } else if model.pendingGate == "production", !model.mediaReady {
                FilmStudioButton("Finish Production Setup") { section = .setup }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            } else if revisionRequired {
                FilmStudioButton("Review Required Changes") { section = .review }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            } else if model.needsHumanReviewDecision {
                FilmStudioButton("Review & Decide…") { showingHumanReview = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
            } else if let gate = model.pendingGate {
                FilmStudioButton("Approve \(model.displayName(gate))") { model.approvePendingGate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApprove)
            } else if model.snapshot != nil, !model.isCompleted {
                if model.canAdvance {
                    FilmStudioButton("Continue Production") { model.advance() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                } else {
                    FilmStudioButton("Finish Required Setup") { section = .setup }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                }
            }

            if model.playableCutURL != nil {
                FilmStudioButton("Play Cut") { model.openPlayableCut() }
            }

            Spacer(minLength: AppTheme.Spacing.md)
            if model.hasInterruptedWork {
                FilmStudioButton("Recover") { model.recover() }
                    .disabled(model.isBusy)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.mdLg)
        .background(AppTheme.Background.baseColor.opacity(AppTheme.Opacity.prominent))
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Image(systemName: symbol)
                .font(.system(size: AppTheme.FontSize.lg))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            Text(verbatim: value)
                .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
                .lineLimit(1)
            Text(verbatim: title)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.lg)
        .background(
            AppTheme.Background.raisedColor,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
        )
    }

    private func optionalField(_ label: String, _ value: String?) -> some View {
        field(label, normalized(value))
    }

    private func normalized(_ value: String?) -> String {
        guard let value, !value.isEmpty, value.lowercased() != "unspecified" else { return "Not set" }
        return value
    }

    private func field(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(verbatim: label)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            Text(verbatim: text)
                .font(.system(size: AppTheme.FontSize.md))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: label).foregroundStyle(AppTheme.Text.tertiaryColor)
            Spacer(minLength: AppTheme.Spacing.md)
            Text(verbatim: value)
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
        }
    }

    private func proof(_ label: String, _ value: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.smMd) {
            Image(systemName: value ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(value ? AppTheme.Status.successColor : AppTheme.Text.mutedColor)
            Text(verbatim: label)
            Spacer(minLength: AppTheme.Spacing.md)
            Text(verbatim: value ? "Passed" : "Pending")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func setupRow(
        title: String,
        detail: String,
        ready: Bool,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
            Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ready ? AppTheme.Status.successColor : AppTheme.Status.warningColor)
                .frame(width: AppTheme.IconSize.smMd)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                Text(verbatim: title)
                    .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                Text(verbatim: detail)
                    .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            Spacer(minLength: AppTheme.Spacing.md)
            if let actionTitle, let action {
                FilmStudioButton(actionTitle, action: action)
                    .disabled(model.isBusy)
            }
        }
        .padding(.vertical, AppTheme.Spacing.smMd)
    }

    private func executableOverride(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(verbatim: label)
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            FilmStudioTextField("Auto-detect", text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isBusy)
        }
    }

    private func agentModelDetail(_ runtime: FilmStudioRuntimeStatus) -> String {
        if let selected = runtime.selectedAgentModel {
            return "\(selected.displayName) · \(selected.id)"
        }
        if let recommended = runtime.recommendedModel {
            return "Recommended for this Mac: \(recommended.displayName) · not installed"
        }
        return runtime.agentError ?? "No startable local producer model is installed"
    }

    private func providerDetail(_ runtime: FilmStudioRuntimeStatus) -> String {
        guard let provider = runtime.agentStatus?.provider else {
            return "Waiting for mere.run producer status"
        }
        if runtime.providerReady {
            return "mere-run · \(provider.modelID ?? "selected model") · \(provider.host ?? "127.0.0.1"):\(provider.port ?? 8080)"
        }
        if provider.configured {
            return "Configured for \(provider.modelID ?? "another model"); reconfigure for the selected model"
        }
        return "Not configured for the selected local producer model"
    }

    private func statusSymbol(_ status: String) -> String {
        switch status.lowercased() {
        case "complete", "completed", "passed", "approved", "delivered": "checkmark.circle.fill"
        case "running", "active", "in-progress": "arrow.triangle.2.circlepath.circle.fill"
        case "failed", "blocked", "error": "exclamationmark.octagon.fill"
        default: "circle"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "complete", "completed", "passed", "approved", "delivered": AppTheme.Status.successColor
        case "running", "active", "in-progress": AppTheme.Accent.timecodeColor
        case "failed", "blocked", "error": AppTheme.Status.errorColor
        default: AppTheme.Text.mutedColor
        }
    }

    private func divider(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        Rectangle()
            .fill(AppTheme.Border.primaryColor)
            .frame(width: width, height: height)
    }
}

@MainActor
private struct FilmStudioCreativeReviewPanel: View {
    @ObservedObject var model: PalmierFilmStudioModel
    let runManifest: URL
    let projectUpdatedAt: String

    @State private var review: FilmStudioCreativeReview?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let review {
                FilmStudioCard(title: "Independent review") {
                    HStack(spacing: AppTheme.Spacing.smMd) {
                        Image(systemName: review.decision == "pass"
                            ? "checkmark.seal.fill"
                            : "arrow.triangle.2.circlepath")
                            .foregroundStyle(review.decision == "pass"
                                ? AppTheme.Status.successColor
                                : AppTheme.Status.warningColor)
                        Text(verbatim: model.displayName(review.decision))
                            .font(.system(size: AppTheme.FontSize.mdLg, weight: AppTheme.FontWeight.medium))
                    }

                    if !review.strengths.isEmpty {
                        reviewList("Strengths", review.strengths)
                    }

                    if !review.rerolls.isEmpty {
                        Text(verbatim: "Requested shot revisions")
                            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                        ForEach(review.rerolls) { reroll in
                            HStack(alignment: .top, spacing: AppTheme.Spacing.smMd) {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Text(verbatim: reroll.shotId)
                                        .font(.system(
                                            size: AppTheme.FontSize.sm,
                                            weight: AppTheme.FontWeight.semibold,
                                            design: .monospaced
                                        ))
                                    Text(verbatim: reroll.note)
                                        .foregroundStyle(AppTheme.Text.secondaryColor)
                                }
                                Spacer(minLength: AppTheme.Spacing.md)
                                FilmStudioButton("Prepare Reroll") {
                                    model.reroll(shotID: reroll.shotId, note: reroll.note)
                                }
                                .disabled(!model.canReroll)
                            }
                            .padding(.vertical, AppTheme.Spacing.xs)
                        }
                    }

                    if !review.issues.isEmpty {
                        Text(verbatim: "Findings")
                            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                        ForEach(review.issues) { issue in
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                                HStack(spacing: AppTheme.Spacing.smMd) {
                                    Text(verbatim: issue.shotId ?? issue.code)
                                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                                    Text(verbatim: model.displayName(issue.severity))
                                        .font(.system(size: AppTheme.FontSize.sm))
                                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                                }
                                Text(verbatim: issue.message)
                                    .foregroundStyle(AppTheme.Text.secondaryColor)
                            }
                        }
                    }

                    if !review.deliveryNotes.isEmpty {
                        reviewList("Delivery notes", review.deliveryNotes)
                    }
                }
            } else if let errorMessage {
                FilmStudioCard(title: "Independent review") {
                    Text(verbatim: errorMessage)
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Status.errorColor)
                        .textSelection(.enabled)
                }
            }
        }
        .task(id: projectUpdatedAt) {
            do {
                review = try await FilmStudioService.loadCreativeReview(runManifest: runManifest)
                errorMessage = nil
            } catch {
                review = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reviewList(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(verbatim: title)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            ForEach(values, id: \.self) { value in
                FilmStudioLabel(value, systemImage: "circle.fill")
                    .font(.system(size: AppTheme.FontSize.smMd))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
            }
        }
    }
}

@MainActor
struct FilmStudioCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            Text(verbatim: title)
                .font(.system(size: AppTheme.FontSize.smMd, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.lg)
            .background(
                AppTheme.Background.raisedColor,
                in: RoundedRectangle(cornerRadius: AppTheme.Radius.mdLg)
            )
        }
    }
}
