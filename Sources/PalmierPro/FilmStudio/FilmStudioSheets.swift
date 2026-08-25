import FilmStudioCore
import SwiftUI

struct NewFilmSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

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
                }
                Text(verbatim: "If that folder already exists, Film Studio automatically uses the next available name.")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.mutedColor)
            }

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer(minLength: AppTheme.Spacing.md)
                Button("Create Film") {
                    model.createFilm()
                    dismiss()
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
    }
}

struct CompleteBriefSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

    @State private var audience: String
    @State private var genre: String
    @State private var tone: String
    @State private var rating: String
    @State private var usage: String
    @State private var references: String

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

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer(minLength: AppTheme.Spacing.md)
                Button("Save Brief") {
                    model.completeBrief(
                        audience: audience,
                        genre: genre,
                        tone: tone,
                        rating: rating,
                        usage: usage,
                        references: references
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete || model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
    }

    private func briefField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(verbatim: title)
                .font(.system(size: AppTheme.FontSize.sm, weight: AppTheme.FontWeight.semibold))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
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

struct ProductionSettingsSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: String
    @State private var takesPerShot: Int

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

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer(minLength: AppTheme.Spacing.md)
                Button("Save & Check Models") {
                    model.configureProduction(mode: mode, takesPerShot: takesPerShot)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
    }
}

struct RerollShotSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    let shot: FilmProductionShot
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

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
            }

            HStack(spacing: AppTheme.Spacing.smMd) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer(minLength: AppTheme.Spacing.md)
                Button("Prepare Reroll") {
                    model.reroll(shotID: shot.id, note: note)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
        }
        .padding(AppTheme.Spacing.xxl)
        .frame(width: AppTheme.Settings.contentMaxWidth)
        .background(AppTheme.Background.baseColor)
    }
}
