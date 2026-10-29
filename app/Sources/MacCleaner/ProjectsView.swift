import SwiftUI

/// Old build folders (node_modules, target, .venv, ...) inside project folders, grouped by project, each with its size
/// and age. Looking changes nothing; deleting happens only on the user's click, through engine/apply.sh --projects.
struct ProjectsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.projectsState {
            case .notLooked:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Project folders").font(.system(size: 30, weight: .bold))
                    Text("Old build folders that tools rebuild on demand: node_modules, target, .venv, .next and similar. Each one is listed with its size and age. Anything in use lately, or in a project with a program running, is held back. Nothing is deleted until you tick it and confirm.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await model.findProjects() }
                    } label: {
                        Text("Look for old build folders").padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
                    Label("It looks in the folders inside your home folder that hold projects. It never opens Documents, Desktop, Downloads or cloud folders, so macOS has nothing to ask.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .looking:
                ProjectsLookView(progress: model.projectsProgress)
            case .deleting:
                LiveCleanView(title: "Deleting what you ticked…", doneLabel: "freed so far",
                              note: "Each folder is checked again just before it goes.",
                              progress: model.cleanProgress, home: model.home)
            case .found:
                foundList
            case .done(let deleted, let freed, let skipped):
                DoneProjects(deleted: deleted, freed: freed, skipped: skipped, home: model.home) { Task { await model.findProjects() } }
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "That didn't work", detail: message,
                            button: "Try again") { Task { await model.findProjects() } }
            }
        }
        .toolbar(removing: .title)
    }

    /// The project folders in the order of what could be freed, each with its build folders.
    private var projects: [(path: String, indices: [Int], bytes: Int64)] {
        let grouped = Dictionary(grouping: model.builds.indices, by: { model.builds[$0].project })
        return grouped.map { project, indices in
            (project, indices.sorted { model.builds[$0].bytes > model.builds[$1].bytes },
             indices.reduce(0) { $0 + model.builds[$1].bytes })
        }
        .sorted { $0.bytes > $1.bytes }
    }

    private var foundList: some View {
        List {
            Section {
                if model.builds.isEmpty {
                    Text("No old build folders found.").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(projects, id: \.path) { project in
                    ProjectHeader(path: project.path, home: model.home, bytes: project.bytes)
                    ForEach(project.indices, id: \.self) { index in
                        BuildRow(build: $model.builds[index])
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    let total = model.builds.reduce(0) { $0 + $1.bytes }
                    Text("\(Bytes.short(total)) in old build folders")
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("\(model.builds.count) folders in \(projects.count) projects. Ticked ones are old and rebuild on demand. Folders in use lately start unticked; a project with a program running cannot be ticked.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .textCase(nil)
                .padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let ticked = model.builds.filter { $0.selected && $0.canTick }
            HStack(spacing: 12) {
                Text("\(ticked.count) ticked").foregroundStyle(.secondary)
                Spacer()
                Button("Look again") { Task { await model.findProjects() } }
                    .controlSize(.large)
                    .help("Run a new look. Nothing is deleted.")
                Button {
                    model.confirmingProjects = true
                } label: {
                    Text("Delete \(Bytes.short(ticked.reduce(0) { $0 + $1.bytes }))…").monospacedDigit().padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(ticked.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .sheet(isPresented: $model.confirmingProjects) {
            ProjectsConfirmSheet(ticked: model.builds.filter { $0.selected && $0.canTick },
                                 onCancel: { model.confirmingProjects = false },
                                 onConfirm: { Task { await model.deleteProjects() } })
        }
    }
}

private struct ProjectHeader: View {
    var path: String
    var home: String
    var bytes: Int64

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 20)
            Text((path as NSString).lastPathComponent).font(.headline)
            Text(path.abbreviatingHome(home))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
                .help(path)
            Spacer(minLength: 16)
            Text(Bytes.short(bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }
}

private struct BuildRow: View {
    @Binding var build: ProjectBuild

    var body: some View {
        HStack(spacing: 10) {
            if build.canTick {
                Toggle("", isOn: $build.selected).labelsHidden().toggleStyle(.checkbox)
            } else {
                Image(systemName: "pause.circle").foregroundStyle(.secondary).frame(width: 16)
            }
            Text(build.name)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(build.canTick ? .primary : .secondary)
                .help(build.path)
            Text(build.ageText())
                .font(.caption)
                .foregroundStyle(build.isRecent ? .orange : .secondary)
            if let note = build.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Text(build.sizeKnown ? Bytes.short(build.bytes) : "size unknown")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 30)
        .padding(.vertical, 1)
    }
}

/// The last stop before project folders are deleted for good, with a warning when ones in use lately are ticked.
struct ProjectsConfirmSheet: View {
    let ticked: [ProjectBuild]
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    var body: some View {
        let bytes = ticked.reduce(0) { $0 + $1.bytes }
        let recent = ticked.filter(\.isRecent).count
        let projects = Set(ticked.map(\.project)).count
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(Bytes.short(bytes))?").font(.title2.bold())
            Text("\(ticked.count) build \(ticked.count == 1 ? "folder" : "folders") in \(projects) \(projects == 1 ? "project" : "projects") are removed for good, not moved to the Trash. Your own files in those projects stay. Tools such as npm and cargo bring the folders back the next time they run. Each path is written to History.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if recent > 0 {
                Label("\(recent) \(recent == 1 ? "is" : "are") in use lately. Deleting \(recent == 1 ? "it" : "them") may break an app or dev server that is open.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button(role: .destructive, action: onConfirm) {
                    Text("Delete \(Bytes.short(bytes))").monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct DoneProjects: View {
    var deleted: Int
    var freed: Int64
    var skipped: [ApplyResult]
    var home: String
    var onAgain: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SuccessHeader(freed: freed)
                Text("\(deleted) build \(deleted == 1 ? "folder" : "folders") deleted. Each one is listed in History.")
                    .foregroundStyle(.secondary)
                if !skipped.isEmpty {
                    Text("Left alone (\(skipped.count))").font(.headline).padding(.top, 10)
                    ForEach(skipped, id: \.self) { result in
                        HStack(alignment: .firstTextBaseline) {
                            Text(result.path.abbreviatingHome(home))
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(result.reason).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Look again", action: onAgain).controlSize(.large).padding(.top, 10)
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
