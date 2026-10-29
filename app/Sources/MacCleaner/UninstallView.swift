import SwiftUI

/// One installed app in the Uninstall list (from `bin/uninstall_scan.sh --list`).
struct InstalledApp: Identifiable, Hashable, Decodable {
    var id: String { path }
    var name: String
    var bundleID: String
    var version: String
    var path: String
    var bytes: Int64
    var lastUsed: String?
}

/// One file or folder an uninstall would move to the Trash.
struct Leftover: Identifiable, Hashable {
    /// The engine's own section names.
    enum Kind: String, CaseIterable {
        case app = "The app", settings = "Settings and saved state", caches = "Caches and logs", data = "Its data",
             services = "Helpers and launch agents", unsure = "Not tied to this app"
        var title: String { self == .unsure ? "Not tied to this app: your look" : rawValue }
    }
    var id: String { path }
    var path: String
    var bytes: Int64
    var kind: Kind
    var note: String?
    var selected: Bool
}

/// What the second look found after the move, in the engine's words.
struct UninstallCheck: Equatable {
    var left: [String]
    var nameOnly: [String]
    var uninspected: [String]
    var incomplete: Bool
}

/// The Uninstall pane's state. Looking changes nothing. Moving to the Trash happens only on the user's click, through
/// engine/apply.sh --uninstall, which checks every ticked path again (and refuses a running app).
@MainActor
final class UninstallModel: ObservableObject {
    enum Stage: Equatable {
        case notLooked, listing, list, planning(String), review, moving, done, failed(String)
    }

    @Published var stage: Stage = .notLooked
    @Published var apps: [InstalledApp] = []
    @Published var search = ""
    @Published var chosen: InstalledApp?
    @Published var leftovers: [Leftover] = []
    @Published var needsAdmin: [String] = []
    @Published var uninspected: [String] = []
    @Published var scanErrors: [String] = []
    @Published var confirming = false
    @Published var moved: [ApplyResult] = []
    @Published var skipped: [ApplyResult] = []
    @Published var check: UninstallCheck?

    let engine: Engine?
    var home: String { engine?.home ?? NSHomeDirectory() }

    init(engine: Engine?) { self.engine = engine }

    var filteredApps: [InstalledApp] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return needle.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(needle) || $0.bundleID.lowercased().contains(needle) }
    }
    var ticked: [Leftover] { leftovers.filter(\.selected) }

    private struct Summary: Decodable {
        var needsAdmin: [String]?
        var uninspected: [String]?
        var errors: [String]?
    }
    private struct CheckAnswer: Decodable {
        var left: [String]?
        var nameOnly: [String]?
        var uninspected: [String]?
        var errors: [String]?
    }

    /// The last line that looks like JSON: the scripts print their answer as one line.
    private func json(_ lines: [String]) -> Data? {
        lines.last { $0.hasPrefix("{") || $0.hasPrefix("[") }?.data(using: .utf8)
    }

    func loadApps() async {
        guard let engine else { stage = .failed(EngineError.notFound.localizedDescription); return }
        stage = .listing
        let output = LineCollector()
        let status = (try? await engine.run("bin/uninstall_scan.sh", ["--list"]) { output.add($0) }) ?? -1
        guard status == 0, let data = json(output.lines), let found = try? JSONDecoder().decode([InstalledApp].self, from: data) else {
            stage = .failed("The list of apps could not be read. Nothing was changed.")
            return
        }
        apps = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        stage = .list
    }

    /// Looks at one app: every file that belongs to it. Changes nothing.
    func look(at app: InstalledApp) async {
        guard let engine else { return }
        chosen = app
        stage = .planning(app.name)
        check = nil
        moved = []
        skipped = []
        let output = LineCollector()
        let plan = engine.uninstallPlanURL
        try? FileManager.default.removeItem(at: plan)
        let status = (try? await engine.run("bin/uninstall_scan.sh", ["--app", app.path, "--plan-out", plan.path]) { output.add($0) }) ?? -1
        guard let data = json(output.lines), let summary = try? JSONDecoder().decode(Summary.self, from: data),
              let records = try? PlanRecord.read(from: plan), !records.isEmpty else {
            stage = .failed("\(app.name) could not be looked at: \(status == 2 ? "it is protected or its identity is unreadable" : "the scan stopped early"). Nothing was changed.")
            return
        }
        needsAdmin = summary.needsAdmin ?? []
        uninspected = summary.uninspected ?? []
        scanErrors = summary.errors ?? []
        leftovers = records.compactMap { record in
            guard let kind = Leftover.Kind(rawValue: record.section) else { return nil }
            return Leftover(path: record.path, bytes: record.kb * 1024, kind: kind,
                            note: kind == .unsure ? "matched by name only" : nil, selected: kind != .unsure)
        }
        stage = .review
    }

    func back() {
        stage = apps.isEmpty ? .notLooked : .list
        chosen = nil
        leftovers = []
    }

    func moveToTrash() async {
        guard let engine, let app = chosen else { return }
        confirming = false
        stage = .moving
        let paths = ticked.map(\.path)
        do {
            let results = try await engine.apply(paths, planFile: engine.uninstallPlanURL, trash: false, uninstall: true)
            moved = results.filter(\.succeeded)
            skipped = results.filter { !$0.succeeded }
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }
        // The second look: the same discovery again, with the app gone.
        let output = LineCollector()
        let status = (try? await engine.run("bin/uninstall_scan.sh", ["--check", app.path]) { output.add($0) }) ?? -1
        if let data = json(output.lines), let answer = try? JSONDecoder().decode(CheckAnswer.self, from: data) {
            check = UninstallCheck(left: answer.left ?? [], nameOnly: answer.nameOnly ?? [], uninspected: answer.uninspected ?? [],
                                   incomplete: status != 0 || !(answer.errors ?? []).isEmpty)
        } else {
            check = UninstallCheck(left: [], nameOnly: [], uninspected: [], incomplete: true)
        }
        apps.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        stage = .done
    }
}

/// The Uninstall pane: pick an app, see every file that goes with it, tick, move to the Trash, then a second look that says
/// whether anything is left.
struct UninstallView: View {
    @ObservedObject var model: UninstallModel
    /// Renders only: an offscreen draw leaves a ScrollView blank, so the done screen can be drawn without one.
    var flat = false

    var body: some View {
        Group {
            switch model.stage {
            case .notLooked: intro
            case .listing: LoadingView(title: "Looking for your apps…", detail: "Reading the apps in Applications. Nothing is changed.")
            case .list: list
            case .planning(let name): LoadingView(title: "Finding everything that belongs to \(name)…", detail: "Looking in your Library folders. Nothing is changed.")
            case .review: review
            case .moving: LoadingView(title: "Moving to the Trash…", detail: "Each item is checked again just before it moves.")
            case .done: done
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "That didn't work", detail: message, button: "Try again") {
                    Task { await model.loadApps() }
                }
            }
        }
        .toolbar(removing: .title)
        .sheet(isPresented: $model.confirming) {
            UninstallConfirmSheet(app: model.chosen?.name ?? "this app", ticked: model.ticked,
                                  onCancel: { model.confirming = false }, onConfirm: { Task { await model.moveToTrash() } })
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Uninstall apps").font(.system(size: 30, weight: .bold))
            Text("Pick an app. You see every file that belongs to it before anything moves, and what goes is moved to the Trash, so it can be put back. Files that only match the app's name start unticked.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { Task { await model.loadApps() } } label: { Text("Show my apps").padding(.horizontal, 8) }
                .buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 6)
            Label("It never closes a running app, never uses admin rights and never touches Apple's apps or Captain Levi. Files that need admin rights are listed and left alone.",
                  systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.filteredApps) { app in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 32, height: 32)
                            .overlay(Text(String(app.name.prefix(1))).font(.headline).foregroundStyle(.secondary))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.headline)
                            Text(app.lastUsed.map { "\(app.version) · last opened \($0)" } ?? app.version)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 16)
                        Text(Bytes.short(app.bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        Button("Look…") { Task { await model.look(at: app) } }.controlSize(.small)
                    }
                    .padding(.vertical, 3)
                }
                if model.filteredApps.isEmpty {
                    Text("No apps match.").foregroundStyle(.secondary).padding(.vertical, 8)
                }
            } header: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Uninstall an app").font(.system(size: 30, weight: .bold))
                    Text("Pick an app. You see every file that belongs to it before anything moves, and what goes is moved to the Trash, so it can be put back.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search \(model.apps.count) apps", text: $model.search).textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.6)))
                }
                .textCase(nil)
                .padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
    }

    private func total(_ kind: Leftover.Kind) -> Int64 { model.leftovers.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes } }

    private var review: some View {
        let ticked = model.ticked
        let name = model.chosen?.name ?? "This app"
        return List {
            Section {
                ForEach(Leftover.Kind.allCases, id: \.self) { kind in
                    let rows = model.leftovers.indices.filter { model.leftovers[$0].kind == kind }
                    if !rows.isEmpty {
                        HStack(spacing: 8) {
                            Text(kind.title).font(.headline)
                            Spacer()
                            Text(Bytes.short(total(kind))).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.top, 12)
                        ForEach(rows, id: \.self) { index in
                            HStack(spacing: 10) {
                                Toggle("", isOn: $model.leftovers[index].selected).labelsHidden().toggleStyle(.checkbox)
                                Text(model.leftovers[index].path.abbreviatingHome(model.home))
                                    .font(.system(.callout, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle)
                                    .help(model.leftovers[index].path)
                                if let note = model.leftovers[index].note {
                                    Text(note).font(.caption).foregroundStyle(.orange)
                                }
                                Spacer(minLength: 16)
                                Text(Bytes.short(model.leftovers[index].bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.leading, 6)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(name) and \(max(model.leftovers.count - 1, 0)) other \(model.leftovers.count == 2 ? "place" : "places")")
                        .font(.system(size: 30, weight: .bold))
                    Text("Ticked items move to the Trash. Anything found by name alone, not by the app's own id, starts unticked: look before you tick it.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !model.needsAdmin.isEmpty {
                        Label("\(model.needsAdmin.count) system-level \(model.needsAdmin.count == 1 ? "file needs" : "files need") admin rights and will be left alone.",
                              systemImage: "lock").font(.callout).foregroundStyle(.secondary)
                    }
                    if !model.scanErrors.isEmpty {
                        Label("The look was incomplete, so this list may be missing files: \(model.scanErrors.prefix(2).joined(separator: "; "))",
                              systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                    }
                }
                .textCase(nil)
                .padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Text("\(ticked.count) of \(model.leftovers.count) ticked").foregroundStyle(.secondary)
                Spacer()
                Button("Back") { model.back() }.controlSize(.large)
                Button { model.confirming = true } label: {
                    Text("Move \(Bytes.short(ticked.reduce(0) { $0 + $1.bytes })) to the Trash…").monospacedDigit().padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(ticked.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var done: some View {
        let name = model.chosen?.name ?? "The app"
        let clean = model.check.map { $0.left.isEmpty && !$0.incomplete } ?? false
        let content = VStack(alignment: .leading, spacing: 14) {
                Image(systemName: model.moved.isEmpty ? "exclamationmark.circle" : "checkmark.circle.fill").font(.system(size: 36))
                    .foregroundStyle(model.moved.isEmpty ? Color.orange : Color.green)
                Text(model.moved.isEmpty ? "Nothing was moved" : "\(name) is in the Trash").font(.system(size: 30, weight: .bold))
                Text("\(model.moved.count) \(model.moved.count == 1 ? "item" : "items") moved, \(Bytes.short(model.moved.reduce(0) { $0 + $1.bytes })) in all. You can put any of them back from the Trash until you empty it. Each one is listed in History.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Looked again in your Library folders, containers, caches, preferences, saved state, logs, launch agents and helper tools",
                          systemImage: "magnifyingglass")
                    if clean {
                        Label("Nothing is left that belongs to \(name)", systemImage: "checkmark.seal").foregroundStyle(.green)
                    } else if model.check?.incomplete == true {
                        Label("The second look could not finish, so it cannot say that nothing is left.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if let left = model.check?.left, !left.isEmpty {
                        Label("\(left.count) \(left.count == 1 ? "item" : "items") still on your Mac that belong to \(name):", systemImage: "hand.raised").foregroundStyle(.orange)
                        ForEach(left, id: \.self) { path in
                            Text(path.abbreviatingHome(model.home)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).padding(.leading, 24)
                        }
                    }
                    if let names = model.check?.nameOnly, !names.isEmpty {
                        Label("\(names.count) \(names.count == 1 ? "item" : "items") matched by name only stayed where \(names.count == 1 ? "it was" : "they were").", systemImage: "hand.raised")
                            .foregroundStyle(.secondary)
                    }
                    Label("Login items and the full list of package receipts are not looked at: check System Settings > General > Login Items.",
                          systemImage: "info.circle").foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
                if !model.skipped.isEmpty {
                    Text("Left alone (\(model.skipped.count))").font(.headline).padding(.top, 6)
                    ForEach(model.skipped, id: \.self) { result in
                        HStack(alignment: .firstTextBaseline) {
                            Text(result.path.abbreviatingHome(model.home)).font(.system(.callout, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(result.reason).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("Open the Trash") { NSWorkspace.shared.open(URL(fileURLWithPath: model.home + "/.Trash")) }.controlSize(.large)
                    Button("Uninstall another") { Task { await model.loadApps() } }.controlSize(.large)
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(40)
        return Group { if flat { content } else { ScrollView { content } } }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LoadingView: View {
    var title: String
    var detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView().controlSize(.regular)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The last stop before an app's files move to the Trash.
struct UninstallConfirmSheet: View {
    var app: String
    var ticked: [Leftover]
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    var body: some View {
        let bytes = ticked.reduce(0) { $0 + $1.bytes }
        VStack(alignment: .leading, spacing: 16) {
            Text("Move \(app) to the Trash?").font(.title2.bold())
            Text("\(ticked.count) \(ticked.count == 1 ? "item" : "items"), \(Bytes.short(bytes)), move to the Trash. Nothing is erased: you can put each one back from the Trash until you empty it. Captain Levi does not close the app: if it is open, it is left alone and you are told. Each item is written to History.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction).controlSize(.large)
                Button(action: onConfirm) { Text("Move \(Bytes.short(bytes)) to the Trash").monospacedDigit() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

extension Fixtures {
    static var installedApps: [InstalledApp] {
        [InstalledApp(name: "Slack", bundleID: "com.tinyspeck.slackmacgap", version: "4.41", path: "/Applications/Slack.app", bytes: 1_140 * MB, lastUsed: nil),
         InstalledApp(name: "Figma", bundleID: "com.figma.Desktop", version: "125.3", path: "/Applications/Figma.app", bytes: 880 * MB, lastUsed: nil),
         InstalledApp(name: "Zoom", bundleID: "us.zoom.xos", version: "6.2", path: "/Applications/Zoom.app", bytes: 610 * MB, lastUsed: nil),
         InstalledApp(name: "Spotify", bundleID: "com.spotify.client", version: "1.2.60", path: "/Applications/Spotify.app", bytes: 540 * MB, lastUsed: nil),
         InstalledApp(name: "Old Player", bundleID: "com.example.oldplayer", version: "2.0", path: "/Applications/Old Player.app", bytes: 210 * MB, lastUsed: nil)]
    }

    static var leftovers: [Leftover] {
        let h = home
        return [
            Leftover(path: "/Applications/Slack.app", bytes: 612 * MB, kind: .app, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Preferences/com.tinyspeck.slackmacgap.plist", bytes: 12_000, kind: .settings, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Saved Application State/com.tinyspeck.slackmacgap.savedState", bytes: 4 * MB, kind: .settings, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Caches/com.tinyspeck.slackmacgap", bytes: 410 * MB, kind: .caches, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Logs/Slack", bytes: 18 * MB, kind: .caches, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Application Support/Slack", bytes: 96 * MB, kind: .data, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Containers/com.tinyspeck.slackmacgap", bytes: 2 * MB, kind: .data, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Group Containers/BQR82RBBHL.com.tinyspeck.slackmacgap", bytes: 1 * MB, kind: .data, note: nil, selected: true),
            Leftover(path: "\(h)/Library/LaunchAgents/com.tinyspeck.slackmacgap.helper.plist", bytes: 800, kind: .services, note: nil, selected: true),
            Leftover(path: "\(h)/Library/Application Support/Slack Helper Tools", bytes: 3 * MB, kind: .unsure, note: "matched by name only", selected: false)]
    }
}
