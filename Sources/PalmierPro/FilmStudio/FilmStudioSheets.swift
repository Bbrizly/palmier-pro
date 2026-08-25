import FilmStudioCore
import Foundation
import SwiftUI

@MainActor
struct NewFilmSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            sheetHeading(
                "New Film",
                "Start with one sentence. GRACE will stop for your brief and creative approvals before production continues."
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                fieldLabel("Idea")
                TextEditor(text: $model.newFilmIdea)
                    .font(.system(size: AppTheme.FontSize.mdLg))
                    .frame(minHeight: AppTheme.Settings.skillRowIconFrame * 2)
                    .padding(AppTheme.Spacing.smMd)
                    .background(
                        AppTheme.Background.raisedColor,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .disabled(model.isBusy)
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.lgXl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    fieldLabel("Working title")
                    FilmStudioTextField("Optional", text: $model.newFilmTitle)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isBusy)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    fieldLabel("Target length")
                    Picker(selection: $model.newFilmDuration) {
                        ForEach(model.durationOptions, id: \.self) { seconds in
                            Text(verbatim: "\(seconds)s").tag(seconds)
                        }
                    } label: {
                        Text(verbatim: "Target length")
                    }
                    .labelsHidden()
                    .disabled(model.isBusy)
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                fieldLabel("Location")
                HStack(spacing: AppTheme.Spacing.smMd) {
                    Text(verbatim: model.newFilmProjectDirectory.path)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: AppTheme.Spacing.md)
                    FilmStudioButton("Choose…") { model.chooseNewFilmDirectory() }
                        .disabled(model.isBusy)
                }
                Text(verbatim: "If that folder already exists, Film Studio automatically uses the next available name.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                FilmStudioButton("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                FilmStudioButton(model.isBusy && submitted ? "Creating…" : "Create Film") {
                    submitted = true
                    model.createFilm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.newFilmIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !model.canCreateFilm
                )
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
        .onChange(of: model.isBusy) { _, busy in
            guard submitted, !busy, model.errorMessage == nil else { return }
            dismiss()
        }
    }
}

@MainActor
struct CompleteBriefSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

    @State private var audience: String
    @State private var genre: String
    @State private var tone: String
    @State private var rating: String
    @State private var usage: String
    @State private var references: String
    @State private var submitted = false

    private static let usageOptions = ["personal", "noncommercial", "commercial"]

    init(model: PalmierFilmStudioModel) {
        self.model = model
        let brief = model.snapshot?.project.brief
        _audience = State(initialValue: Self.clean(brief?.audience))
        _genre = State(initialValue: Self.clean(brief?.genre))
        _tone = State(initialValue: Self.clean(brief?.tone))
        _rating = State(initialValue: Self.clean(brief?.rating))
        let currentUsage = Self.clean(brief?.usage)
        _usage = State(initialValue: Self.usageOptions.contains(currentUsage) ? currentUsage : "personal")
        _references = State(initialValue: brief?.references.joined(separator: "\n") ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            sheetHeading(
                "Complete Brief",
                "Confirm the creative boundaries before approving the brief."
            )

            HStack(alignment: .top, spacing: AppTheme.Spacing.lgXl) {
                briefField("Audience", text: $audience, placeholder: "Who is this for?")
                briefField("Genre", text: $genre, placeholder: "Drama, comedy, documentary…")
            }
            HStack(alignment: .top, spacing: AppTheme.Spacing.lgXl) {
                briefField("Tone", text: $tone, placeholder: "How should it feel?")
                briefField("Rating", text: $rating, placeholder: "PG, family-safe, mature…")
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                fieldLabel("Intended use")
                Picker(selection: $usage) {
                    Text(verbatim: "Personal").tag("personal")
                    Text(verbatim: "Noncommercial").tag("noncommercial")
                    Text(verbatim: "Commercial").tag("commercial")
                } label: {
                    Text(verbatim: "Intended use")
                }
                .labelsHidden()
                .disabled(model.isBusy)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                fieldLabel("References")
                TextEditor(text: $references)
                    .font(.system(size: AppTheme.FontSize.md))
                    .frame(minHeight: AppTheme.Settings.skillRowIconFrame * 2)
                    .padding(AppTheme.Spacing.smMd)
                    .background(
                        AppTheme.Background.raisedColor,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .disabled(model.isBusy)
                Text(verbatim: "One reference per line. Leave blank to explicitly confirm there are no specific references.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                FilmStudioButton("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                FilmStudioButton(model.isBusy && submitted ? "Saving…" : "Save Brief") {
                    submitted = true
                    model.completeBrief(
                        audience: audience,
                        genre: genre,
                        tone: tone,
                        rating: rating,
                        usage: usage,
                        references: references
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete || model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
        .onChange(of: model.isBusy) { _, busy in
            guard submitted, !busy, model.errorMessage == nil else { return }
            dismiss()
        }
    }

    private func briefField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            fieldLabel(title)
            FilmStudioTextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isBusy)
        }
        .frame(maxWidth: .infinity)
    }

    private var isComplete: Bool {
        [audience, genre, tone, rating]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func clean(_ value: String?) -> String {
        guard let value, value.lowercased() != "unspecified" else { return "" }
        return value
    }
}

@MainActor
struct ProductionSettingsSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: String
    @State private var takesPerShot: Int
    @State private var submitted = false

    init(model: PalmierFilmStudioModel) {
        self.model = model
        let production = model.snapshot?.project.production
        _mode = State(initialValue: production?.mode == "final" ? "final" : "draft")
        _takesPerShot = State(initialValue: production?.takesPerShot ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            sheetHeading(
                "Production Settings",
                "Choose the render cost before approving production. Saving runs model preflight without generating media."
            )

            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                fieldLabel("Render mode")
                Picker(selection: $mode) {
                    Text(verbatim: "Draft — faster iteration").tag("draft")
                    Text(verbatim: "Final — full-quality render").tag("final")
                } label: {
                    Text(verbatim: "Render mode")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isBusy)
                Text(verbatim: mode == "draft"
                    ? "Use draft settings for the first complete cut and faster iteration."
                    : "Use final-quality media settings when the production plan is ready for the full local compute budget.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                fieldLabel("Takes per shot")
                Picker(selection: $takesPerShot) {
                    ForEach(1...4, id: \.self) { count in
                        Text(verbatim: "\(count)").tag(count)
                    }
                } label: {
                    Text(verbatim: "Takes per shot")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isBusy)
                Text(verbatim: takesPerShot == 1
                    ? "One candidate per shot. Lowest compute and storage use."
                    : "Generate \(takesPerShot) candidates per shot and select among them. Compute and storage scale with the number of takes.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            if model.productionModelReadinessBlocked {
                FilmStudioLabel(
                    "The previous model preflight failed. Saving again reruns it after the required models are available.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.warningColor)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                FilmStudioButton("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                FilmStudioButton(model.isBusy && submitted ? "Checking Models…" : "Save & Check Models") {
                    submitted = true
                    model.configureProduction(mode: mode, takesPerShot: takesPerShot)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
        .onChange(of: model.isBusy) { _, busy in
            guard submitted, !busy, model.errorMessage == nil else { return }
            dismiss()
        }
    }
}

@MainActor
struct HumanReviewSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

    @State private var decision = "approve"
    @State private var generalNote = ""
    @State private var selectedShotIDs: Set<String> = []
    @State private var shotNotes: [String: String] = [:]
    @State private var submitted = false

    private var shots: [FilmProductionShot] {
        model.snapshot?.productionPlan?.shots ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            sheetHeading(
                "Human Review",
                "Your decision is bound to the exact current cut and its review evidence. Changing the cut invalidates this approval."
            )

            Picker(selection: $decision) {
                Text(verbatim: "Approve Cut").tag("approve")
                Text(verbatim: "Request Revisions").tag("revise")
            } label: {
                Text(verbatim: "Decision")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isBusy)

            if decision == "approve" {
                FilmStudioLabel(
                    "I reviewed the current cut and approve this exact version for picture lock.",
                    systemImage: "checkmark.seal"
                )
                .font(.system(size: AppTheme.FontSize.md))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    fieldLabel("Shots to revise")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                            ForEach(shots) { shot in
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Toggle(isOn: shotSelection(shot.id)) {
                                        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.smMd) {
                                            Text(verbatim: shot.id)
                                                .font(.system(
                                                    size: AppTheme.FontSize.sm,
                                                    weight: AppTheme.FontWeight.semibold,
                                                    design: .monospaced
                                                ))
                                            Text(verbatim: shot.purpose)
                                                .lineLimit(1)
                                        }
                                    }
                                    .disabled(model.isBusy)
                                    if selectedShotIDs.contains(shot.id) {
                                        FilmStudioTextField(
                                            "What should change in this shot?",
                                            text: shotNote(shot.id)
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(model.isBusy)
                                    }
                                }
                                .padding(AppTheme.Spacing.smMd)
                                .background(
                                    AppTheme.Background.raisedColor,
                                    in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: AppTheme.Settings.skillDetailMinHeight / 2)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        fieldLabel("Overall note")
                        TextEditor(text: $generalNote)
                            .frame(minHeight: AppTheme.Settings.skillRowIconFrame * 1.5)
                            .padding(AppTheme.Spacing.smMd)
                            .background(
                                AppTheme.Background.raisedColor,
                                in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            )
                            .disabled(model.isBusy)
                    }
                }
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                FilmStudioButton("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                FilmStudioButton(submitTitle) {
                    submitted = true
                    model.recordReviewDecision(
                        decision: decision,
                        note: generalNote.trimmingCharacters(in: .whitespacesAndNewlines),
                        rerolls: rerolls
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
        .onChange(of: decision) { _, _ in
            model.dismissMessages()
            submitted = false
        }
        .onChange(of: model.isBusy) { _, busy in
            guard submitted, !busy, model.errorMessage == nil else { return }
            dismiss()
        }
    }

    private var rerolls: [FilmStudioReviewReroll] {
        selectedShotIDs.sorted().compactMap { shotID in
            let note = (shotNotes[shotID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { return nil }
            return FilmStudioReviewReroll(shotID: shotID, note: note)
        }
    }

    private var canSubmit: Bool {
        if decision == "approve" { return true }
        return !selectedShotIDs.isEmpty && rerolls.count == selectedShotIDs.count
    }

    private var submitTitle: String {
        if model.isBusy && submitted {
            return decision == "approve" ? "Recording Approval…" : "Recording Revisions…"
        }
        return decision == "approve" ? "Approve This Cut" : "Request Revisions"
    }

    private func shotSelection(_ shotID: String) -> Binding<Bool> {
        Binding(
            get: { selectedShotIDs.contains(shotID) },
            set: { selected in
                if selected {
                    selectedShotIDs.insert(shotID)
                } else {
                    selectedShotIDs.remove(shotID)
                    shotNotes.removeValue(forKey: shotID)
                }
            }
        )
    }

    private func shotNote(_ shotID: String) -> Binding<String> {
        Binding(
            get: { shotNotes[shotID] ?? "" },
            set: { shotNotes[shotID] = $0 }
        )
    }
}

@MainActor
struct RerollShotSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    let shot: FilmProductionShot
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var submitted = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
            sheetHeading("Reroll \(shot.id)", shot.purpose)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                fieldLabel("What should change?")
                TextEditor(text: $note)
                    .font(.system(size: AppTheme.FontSize.md))
                    .frame(minHeight: AppTheme.Settings.skillRowIconFrame * 2)
                    .padding(AppTheme.Spacing.smMd)
                    .background(
                        AppTheme.Background.raisedColor,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                    .disabled(model.isBusy)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                FilmStudioButton("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                FilmStudioButton(model.isBusy && submitted ? "Preparing…" : "Prepare Reroll") {
                    submitted = true
                    model.reroll(shotID: shot.id, note: note)
                }
                .buttonStyle(.borderedProminent)
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
        .onChange(of: model.isBusy) { _, busy in
            guard submitted, !busy, model.errorMessage == nil else { return }
            dismiss()
        }
    }
}

@MainActor
private struct FilmStudioSheetError: View {
    @ObservedObject var model: PalmierFilmStudioModel
    let submitted: Bool

    var body: some View {
        if submitted, let error = model.errorMessage {
            FilmStudioLabel(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.errorColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@MainActor
private func sheetHeading(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
        Text(verbatim: title)
            .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
            .foregroundStyle(AppTheme.Text.primaryColor)
        Text(verbatim: subtitle)
            .font(.system(size: AppTheme.FontSize.md))
            .foregroundStyle(AppTheme.Text.tertiaryColor)
    }
}

@MainActor
private func fieldLabel(_ title: String) -> some View {
    Text(verbatim: title)
        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
        .foregroundStyle(AppTheme.Text.tertiaryColor)
}
