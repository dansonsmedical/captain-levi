import SwiftUI

/// The app's state: a dry run first, a review, the user's click, then the result.
@MainActor
final class AppModel: ObservableObject {
    enum CleanState: Equatable {
        case idle
        case scanning(String)
        case reviewing
        case cleaning
        case done(freed: Int64, cleaned: Int, skipped: [ApplyResult])
        case failed(String)
    }

    enum InstallersState: Equatable {
        case notLooked
        case looking
        case found
        case moving
        case done(moved: Int, freed: Int64, skipped: [ApplyResult])
        case failed(String)
    }

    enum ProjectsState: Equatable {
        case notLooked
        case looking(String)
        case found
        case deleting
        case done(deleted: Int, freed: Int64, skipped: [ApplyResult])
        case failed(String)
    }

    @Published var projectsState: ProjectsState = .notLooked
    @Published var builds: [ProjectBuild] = []
    @Published var confirmingProjects = false
    @Published var state: CleanState = .idle
    /// Set by the menu bar card: the window shows this pane next.
    @Published var requestedPane: Pane?
    @Published var plan: CleanPlan?
    @Published var confirming = false
    @Published var installersState: InstallersState = .notLooked
    @Published var installers: [CleanItem] = []
    @Published var confirmingInstallers = false
    @Published var history: [HistoryEntry] = []
    /// What the working screens show while a scan, a clean or a look runs (set directly by the renders).
    @Published var scanProgress = ScanProgress()
    @Published var cleanProgress = CleanProgress()
    @Published var projectsProgress = ProjectsLookProgress()

    /// The task that watches the plan file (scan) or the history file (clean, move, delete) while the engine runs.
    private var watcher: Task<Void, Never>?

    let engine: Engine?
    let uninstall: UninstallModel
    var home: String { engine?.home ?? NSHomeDirectory() }

    init(engine: Engine?) {
        self.engine = engine
        uninstall = UninstallModel(engine: engine)
        history = engine?.history() ?? []
    }

    // MARK: Watching the engine

    /// While a dry run runs, clean.sh appends each found item to the plan file; read what is new every 0.4 s.
    private func watchScan(plan url: URL) {
        watcher?.cancel()
        // Gone before the first look, so an older plan is never read as this scan's.
        try? FileManager.default.removeItem(at: url)
        watcher = Task { [weak self] in
            var offset = 0
            while !Task.isCancelled {
                let (records, next) = PlanRecord.readNew(from: url, offset: offset)
                offset = next
                if !records.isEmpty, let self { self.scanProgress.add(records, home: self.home) }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    /// While apply.sh runs it appends one history line per item; the offset is taken now, before it starts.
    private func watchHistory(of engine: Engine, total: Int) {
        watcher?.cancel()
        cleanProgress = CleanProgress(startedAt: Date(), total: total)
        let url = engine.historyURL
        var offset = FileTail.size(of: url)
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                let (lines, next) = FileTail.newLines(from: url, offset: offset)
                offset = next
                if !lines.isEmpty, let self { self.cleanProgress.add(lines: lines) }
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    private func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    // MARK: Clean

    func scan() async {
        guard let engine else {
            state = .failed(EngineError.notFound.localizedDescription)
            return
        }
        state = .scanning("Starting")
        scanProgress = ScanProgress()
        watchScan(plan: engine.planURL)
        defer { stopWatching() }
        do {
            let records = try await engine.scan { section in
                Task { @MainActor in
                    if case .scanning = self.state {
                        self.state = .scanning(section)
                        self.scanProgress.setActive(section)
                    }
                }
            }
            let disk = Engine.disk(home: engine.home)
            plan = CleanPlan(groups: Policy.groups(from: records, home: engine.home), scannedAt: Date(),
                             diskFreeBytes: disk.free, diskTotalBytes: disk.total, planFile: engine.planURL)
            state = .reviewing
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func clean() async {
        guard let engine, let plan, let planFile = plan.planFile else { return }
        confirming = false
        state = .cleaning
        let paths = plan.selectedPaths
        watchHistory(of: engine, total: paths.count)
        defer { stopWatching() }
        do {
            let results = try await engine.apply(paths, planFile: planFile, trash: false)
            let done = results.filter(\.succeeded)
            state = .done(freed: done.reduce(0) { $0 + $1.bytes }, cleaned: done.count,
                          skipped: results.filter { !$0.succeeded })
            self.plan = nil
            history = engine.history()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Project folders

    func findProjects() async {
        guard let engine else {
            projectsState = .failed(EngineError.notFound.localizedDescription)
            return
        }
        projectsState = .looking("your project folders")
        projectsProgress = ProjectsLookProgress()
        do {
            let found = try await engine.scanProjects { line in
                // "➤ Looking in NAME" arrives here as "Looking in NAME".
                let name = line.hasPrefix("Looking in ") ? String(line.dropFirst("Looking in ".count)) : line
                Task { @MainActor in
                    if case .looking = self.projectsState {
                        self.projectsState = .looking(name)
                        self.projectsProgress.look(in: name)
                    }
                }
            }
            builds = Policy.projectBuilds(from: found.records, meta: found.meta, home: engine.home)
            projectsState = .found
        } catch {
            projectsState = .failed(error.localizedDescription)
        }
    }

    func deleteProjects() async {
        guard let engine else { return }
        confirmingProjects = false
        projectsState = .deleting
        let ticked = builds.filter { $0.selected && $0.canTick }
        watchHistory(of: engine, total: ticked.count)
        defer { stopWatching() }
        do {
            let results = try await engine.apply(ticked.map(\.path), planFile: engine.projectsPlanURL, trash: false,
                                                 projects: true, allowRecent: ticked.filter(\.isRecent).map(\.path))
            let done = results.filter(\.succeeded)
            projectsState = .done(deleted: done.count, freed: done.reduce(0) { $0 + $1.bytes },
                                  skipped: results.filter { !$0.succeeded })
            builds = []
            history = engine.history()
        } catch {
            projectsState = .failed(error.localizedDescription)
        }
    }

    // MARK: Old installers

    func findInstallers() async {
        guard let engine else {
            installersState = .failed(EngineError.notFound.localizedDescription)
            return
        }
        installersState = .looking
        let records = await Task.detached { engine.findInstallers() }.value
        do {
            try PlanRecord.write(records, to: engine.installerPlanURL)
            installers = records.map { CleanItem(path: $0.path, bytes: $0.kb * 1024, selected: false) }
            installersState = .found
        } catch {
            installersState = .failed(error.localizedDescription)
        }
    }

    func moveInstallersToTrash() async {
        guard let engine else { return }
        confirmingInstallers = false
        installersState = .moving
        let paths = installers.filter(\.selected).map(\.path)
        watchHistory(of: engine, total: paths.count)
        defer { stopWatching() }
        do {
            let results = try await engine.apply(paths, planFile: engine.installerPlanURL, trash: true)
            let moved = results.filter(\.succeeded)
            installersState = .done(moved: moved.count, freed: moved.reduce(0) { $0 + $1.bytes },
                                    skipped: results.filter { !$0.succeeded })
            installers = []
            history = engine.history()
        } catch {
            installersState = .failed(error.localizedDescription)
        }
    }
}
