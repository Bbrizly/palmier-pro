import FilmStudioCore
import SwiftUI

@MainActor
struct FilmStudioWorkspaceView: View {
    enum Section: String, CaseIterable, Identifiable, Hashable {
        case studio, development, shots, review, delivery, runtime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .studio: "Studio"
            case .development: "Development"
            case .shots: "Shots"
            case .review: "Review"
            case .delivery: "Delivery"
            case .runtime: "Runtime"
            }
        }
        var symbol: String {
            switch self {
            case .studio: "square.grid.2x2"
            case .development: "text.book.closed"
            case .shots: "rectangle.stack.badge.play"
            case .review: "checkmark.seal"
            case .delivery: "shippingbox"
            case .runtime: "wrench.and.screwdriver"
            }
        }
    }

    @ObservedObject var model: PalmierFilmStudioModel
    let bridge: FilmStudioPalmierBridge
    @State private var section: Section = .studio
    @State private var showingNewFilm = false

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Film Studio")
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 220)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                messageArea
                content
                Divider()
                actionBar
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 980, minHeight: 660)
        .sheet(isPresented: $showingNewFilm) { NewFilmSheet(model: model) }
        .task { await model.refreshRuntime() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.snapshot?.project.title ?? "GRACE Film Studio")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.activity).font(.caption).foregroundStyle(.secondary)
            }
            Button("Open Film…") { model.chooseProject() }
            Button("New Film") { showingNewFilm = true }.buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        guard let project = model.snapshot?.project else {
            return "GRACE produces the film. Palmier remains the editor."
        }
        return "\(project.phase.capitalized) · \(project.status.capitalized)"
    }

    @ViewBuilder
    private var messageArea: some View {
        if let error = model.errorMessage {
            messageBanner(error, symbol: "exclamationmark.triangle.fill")
        } else if let notice = model.noticeMessage {
            messageBanner(notice, symbol: "checkmark.circle.fill")
        }
    }

    private func messageBanner(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            Button { model.dismissMessages() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.35))
    }

    @ViewBuilder
    private var content: some View {
        if section == .runtime {
            runtimeView
        } else if let snapshot = model.snapshot {
            switch section {
            case .studio: studioView(snapshot)
            case .development: developmentView(snapshot)
            case .shots: shotsView(snapshot)
            case .review: reviewView(snapshot)
            case .delivery: deliveryView(snapshot)
            case .runtime: EmptyView()
            }
        } else {
            ContentUnavailableView {
                Label("No Film Open", systemImage: "movieclapper")
            } description: {
                Text("Create a GRACE film or open an existing run.json. A generated cut can be imported directly into Palmier.")
            } actions: {
                HStack {
                    Button("Open Film…") { model.chooseProject() }
                    Button("New Film") { showingNewFilm = true }.buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func studioView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    metric("Phase", snapshot.project.phase.capitalized, "arrow.triangle.2.circlepath")
                    metric("Shots", String(snapshot.project.shots.count), "rectangle.stack")
                    metric("Checks", "\(snapshot.project.proof.completedCount)/10", "checkmark.seal")
                    metric("Blocking", String(snapshot.project.issues.filter(\.blocking).count), "exclamationmark.triangle")
                }
                GroupBox("Production proof") {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: Double(snapshot.project.proof.completedCount), total: 10)
                        Text("\(snapshot.project.proof.completedCount) of 10 delivery checks complete")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                GroupBox("Departments") {
                    VStack(spacing: 0) {
                        if snapshot.project.departments.isEmpty {
                            Text("No department tasks yet.").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        } else {
                            ForEach(snapshot.project.departments) { department in
                                HStack {
                                    Image(systemName: statusSymbol(department.status)).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(department.role.replacingOccurrences(of: "-", with: " ").capitalized)
                                        Text(department.phase.capitalized).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(department.status.capitalized).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func metric(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }

    private func developmentView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let treatment = snapshot.treatment {
                    GroupBox("Treatment") {
                        VStack(alignment: .leading, spacing: 14) {
                            field("Logline", treatment.logline)
                            field("Synopsis", treatment.synopsis)
                            field("Theme", treatment.theme)
                            field("Visual language", treatment.visualLanguage)
                            field("Sound language", treatment.soundLanguage)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                    GroupBox("Story beats") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(treatment.beats.enumerated()), id: \.offset) { index, beat in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(String(index + 1)).font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                                    Text(beat).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    ContentUnavailableView("Treatment Not Ready", systemImage: "text.book.closed", description: Text("Advance production until GRACE writes the treatment."))
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(18)
        }
    }

    private func field(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shotsView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let shots = snapshot.productionPlan?.shots, !shots.isEmpty {
                    ForEach(shots) { shot in
                        let state = snapshot.project.shots.first { $0.id == shot.id }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(shot.id).font(.caption.monospaced().weight(.semibold)).foregroundStyle(.secondary)
                                Text(shot.purpose).font(.headline).lineLimit(1)
                                Spacer()
                                Text(state?.status?.capitalized ?? shot.status.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(shot.prompt).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                            HStack(spacing: 14) {
                                Label(String(format: "%.1fs", shot.durationSeconds), systemImage: "clock")
                                Label("Take \(state?.take ?? shot.take)", systemImage: "film.stack")
                                if !shot.characters.isEmpty {
                                    Label(shot.characters.joined(separator: ", "), systemImage: "person.2").lineLimit(1)
                                }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    ContentUnavailableView("Shot Plan Not Ready", systemImage: "rectangle.stack.badge.play", description: Text("Approve development and advance GRACE to production planning."))
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(18)
        }
    }

    private func reviewView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Issues") {
                    VStack(spacing: 0) {
                        if snapshot.project.issues.isEmpty {
                            Label("No recorded issues", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        } else {
                            ForEach(snapshot.project.issues) { issue in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: issue.blocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(issue.code).font(.caption.monospaced().weight(.semibold))
                                        Text(issue.message)
                                    }
                                    Spacer()
                                    if issue.blocking { Text("Blocking").font(.caption.weight(.semibold)) }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                GroupBox("Review requests") {
                    VStack(spacing: 0) {
                        if snapshot.project.reviewRequests.isEmpty {
                            Text("No targeted reroll requests.").foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                        } else {
                            ForEach(snapshot.project.reviewRequests) { request in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(request.shotId).font(.caption.monospaced().weight(.semibold))
                                        Spacer()
                                        Text(request.status.capitalized).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(request.note)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private func deliveryView(_ snapshot: FilmWorkspaceSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Palmier handoff") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let cut = snapshot.playableCutURL {
                            Label(cut.lastPathComponent, systemImage: "film").font(.headline)
                            Text(cut.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled).lineLimit(2)
                            HStack {
                                Button("Import Cut into Palmier") { bridge.importPlayableCut(using: model) }
                                    .buttonStyle(.borderedProminent).disabled(model.isBusy)
                                Button("Reveal in Finder") { model.revealPlayableCut() }
                            }
                            Text("The cut imports into whichever Palmier project is active when you click the button.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("No playable cut exists yet. GRACE exposes its rough cut, final master, or delivery master here as soon as one is produced.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                GroupBox("Delivery checks") {
                    VStack(spacing: 0) {
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
                    .padding(.vertical, 4)
                }
            }
            .padding(18)
        }
    }

    private func proof(_ label: String, _ value: Bool) -> some View {
        HStack {
            Image(systemName: value ? "checkmark.circle.fill" : "circle")
            Text(label)
            Spacer()
            Text(value ? "Passed" : "Pending").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    private var runtimeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Executable paths") {
                    VStack(alignment: .leading, spacing: 12) {
                        executableField("mere-film-tools", $model.filmToolExecutable)
                        executableField("mere.run", $model.mereRunExecutable)
                        executableField("Pi", $model.piExecutable)
                        HStack {
                            Spacer()
                            Button("Recheck Runtime") { Task { await model.refreshRuntime() } }.disabled(model.isBusy)
                        }
                    }
                    .padding(.vertical, 6)
                }
                GroupBox("Runtime health") {
                    VStack(spacing: 0) {
                        ForEach(model.runtimeDependencies) { dependency in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: dependency.available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dependency.label).font(.callout.weight(.medium))
                                    Text(dependency.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .textSelection(.enabled).lineLimit(2)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                Text("FilmStudioCore is integrated directly. The GRACE runtime remains local and explicit, so missing executables are reported here instead of failing silently.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private func executableField(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 120, alignment: .leading)
            TextField("Executable name or absolute path", text: text)
                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if model.snapshot != nil {
            HStack(spacing: 10) {
                if let gate = model.pendingGate {
                    Button("Approve \(gate.replacingOccurrences(of: "-", with: " ").capitalized)") { model.approvePendingGate() }
                        .buttonStyle(.borderedProminent).disabled(model.isBusy)
                }
                Button("Advance") { model.advance() }.disabled(model.isBusy || !model.runtimeReady)
                Button("Run Review") { model.runReview() }.disabled(model.isBusy || !model.runtimeReady)
                Button("Recover") { model.recover() }.disabled(model.isBusy)
                Spacer()
                Button {
                    model.refreshProject()
                    Task { await model.refreshRuntime() }
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .disabled(model.isBusy)
                Button("Close Film") { model.closeProject() }.disabled(model.isBusy)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
    }

    private func statusSymbol(_ status: String) -> String {
        switch status.lowercased() {
        case "complete", "completed", "done", "passed", "approved": "checkmark.circle.fill"
        case "running", "active", "in-progress": "clock.arrow.circlepath"
        case "failed", "blocked", "error": "exclamationmark.octagon.fill"
        default: "circle"
        }
    }
}

@MainActor
private struct NewFilmSheet: View {
    @ObservedObject var model: PalmierFilmStudioModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New GRACE Film").font(.title2.weight(.semibold))
                Text("Give GRACE the idea. Palmier handles the edit after production.").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Idea").font(.caption.weight(.semibold))
                TextEditor(text: $model.newFilmIdea).frame(minHeight: 110)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Working title").font(.caption.weight(.semibold))
                TextField("Untitled film", text: $model.newFilmTitle).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Target length").font(.caption.weight(.semibold))
                Picker("Target length", selection: $model.newFilmDuration) {
                    ForEach(model.durationOptions, id: \.self) { seconds in Text("\(seconds)s").tag(seconds) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Location").font(.caption.weight(.semibold))
                    Text(model.newFilmDirectory.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Choose…") { model.chooseNewFilmDirectory() }
            }
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Film") {
                    model.createFilm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(model.newFilmIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
            }
        }
        .padding(22).frame(width: 640)
    }
}
