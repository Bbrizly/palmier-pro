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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "New Film")
                    .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Text(verbatim: "Start with one sentence. GRACE will stop for your brief and creative approvals before production continues.")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Idea")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                TextEditor(text: $model.newFilmIdea)
                    .font(.system(size: AppTheme.FontSize.mdLg))
                    .frame(minHeight: AppTheme.Settings.skillRowIconFrame * 2)
                    .padding(AppTheme.Spacing.smMd)
                    .background(
                        AppTheme.Background.raisedColor,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.lgXl) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(verbatim: "Working title")
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    TextField("Optional", text: $model.newFilmTitle)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(verbatim: "Target length")
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    Picker("Target length", selection: $model.newFilmDuration) {
                        ForEach(model.durationOptions, id: \.self) { seconds in
                            Text("\(seconds)s").tag(seconds)
                        }
                    }
                    .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Location")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                HStack(spacing: AppTheme.Spacing.smMd) {
                    Text(verbatim: model.newFilmProjectDirectory.path)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: AppTheme.Spacing.md)
                    Button("Choose…") {
                        model.chooseNewFilmDirectory()
                    }
                    .disabled(model.isBusy)
                }
                Text(verbatim: "If that folder already exists, Film Studio automatically uses the next available name.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                Button(model.isBusy && submitted ? "Creating…" : "Create Film") {
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
            dismissAfterSuccessfulSubmission(busy: busy)
        }
    }

    private func dismissAfterSuccessfulSubmission(busy: Bool) {
        guard submitted, !busy, model.errorMessage == nil else { return }
        dismiss()
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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Complete Brief")
                    .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
                Text(verbatim: "GRACE will not greenlight its own assumptions. Confirm the creative boundaries before approving the brief.")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            HStack(alignment: .top, spacing: AppTheme.Spacing.lgXl) {
                briefField("Audience", text: $audience, placeholder: "Who is this for?")
                briefField("Genre", text: $genre, placeholder: "Drama, comedy, documentary…")
            }
            HStack(alignment: .top, spacing: AppTheme.Spacing.lgXl) {
                briefField("Tone", text: $tone, placeholder: "How should it feel?")
                briefField("Rating", text: $rating, placeholder: "PG, family-safe, mature…")
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Intended use")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Picker("Intended use", selection: $usage) {
                    Text("Personal").tag("personal")
                    Text("Noncommercial").tag("noncommercial")
                    Text("Commercial").tag("commercial")
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "References")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                TextEditor(text: $references)
                    .font(.system(size: AppTheme.FontSize.md))
                    .frame(minHeight: AppTheme.Settings.skillRowIconFrame * 2)
                    .padding(AppTheme.Spacing.smMd)
                    .background(
                        AppTheme.Background.raisedColor,
                        in: RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    )
                Text(verbatim: "One reference per line. Leave blank to explicitly confirm there are no specific references.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                Button(model.isBusy && submitted ? "Saving…" : "Save Brief") {
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
            Text(verbatim: title)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            TextField(placeholder, text: text)
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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Production Settings")
                    .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
                Text(verbatim: "Choose the render cost before approving production. GRACE will run a model preflight without generating media.")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                Text(verbatim: "Render mode")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Picker("Render mode", selection: $mode) {
                    Text("Draft — faster iteration").tag("draft")
                    Text("Final — full-quality render").tag("final")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isBusy)
                Text(verbatim: mode == "draft"
                    ? "Uses draft video settings and video-only shot renders where GRACE supports them. Best for the first complete cut."
                    : "Uses final-quality media settings and audio-video shot renders. Use when you are ready to spend the full local compute budget.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                Text(verbatim: "Takes per shot")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Picker("Takes per shot", selection: $takesPerShot) {
                    ForEach(1...4, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(model.isBusy)
                Text(verbatim: takesPerShot == 1
                    ? "One candidate per shot. Lowest compute and storage use."
                    : "GRACE generates \(takesPerShot) candidates per shot and selects among them. Compute and storage increase roughly with the number of takes.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            if model.productionModelReadinessBlocked {
                Label(
                    "The previous model preflight failed. Saving again reruns preflight after you install or change the required models.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.warningColor)
            }

            FilmStudioSheetError(model: model, submitted: submitted)

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                Button(model.isBusy && submitted ? "Checking Models…" : "Save & Check Models") {
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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Human Review")
                    .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
                Text(verbatim: "Your decision is bound to the exact current cut and review evidence. Changing the cut later invalidates this approval.")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            Picker("Decision", selection: $decision) {
                Text("Approve Cut").tag("approve")
                Text("Request Revisions").tag("revise")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.isBusy)

            if decision == "approve" {
                Label(
                    "I reviewed the current playable cut and the recorded review evidence and approve this exact version for picture lock.",
                    systemImage: "checkmark.seal"
                )
                .font(.system(size: AppTheme.FontSize.md))
                .foregroundStyle(AppTheme.Text.secondaryColor)
            } else {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                    Text(verbatim: "Shots to revise")
                        .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
                            ForEach(shots) { shot in
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    Toggle(isOn: shotSelection(shot.id)) {
                                        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.smMd) {
                                            Text(verbatim: shot.id)
                                                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold, design: .monospaced))
                                            Text(verbatim: shot.purpose)
                                                .lineLimit(1)
                                        }
                                    }
                                    .disabled(model.isBusy)
                                    if selectedShotIDs.contains(shot.id) {
                                        TextField("What should change in this shot?", text: shotNote(shot.id))
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
                        Text(verbatim: "Overall note")
                            .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
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
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                Button(submitTitle) {
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
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "Reroll \(shot.id)")
                    .font(.system(size: AppTheme.FontSize.title1, weight: AppTheme.FontWeight.semibold))
                Text(verbatim: shot.purpose)
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(verbatim: "What should change?")
                    .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
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
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(model.isBusy)
                Spacer(minLength: AppTheme.Spacing.md)
                Button(model.isBusy && submitted ? "Preparing…" : "Prepare Reroll") {
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
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Status.errorColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
