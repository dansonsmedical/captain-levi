import AppKit
import Dispatch
import SwiftUI

@main
enum Entry {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--updater-selftest") {
            let arguments = Array(args.dropFirst(i + 1))
            Task { @MainActor in exit(await UpdaterSelfTest.run(arguments)) }
            dispatchMain()
        }
        // Shell-test entry point: inspect the real bundle without starting the app or scanning HOME.
        if let i = args.firstIndex(of: "--check-release-engine"), i + 1 < args.count {
            guard let root = Engine.locateRoot(),
                  let engine = try? Engine(root: root, home: ProcessInfo.processInfo.environment["HOME"] ?? "",
                                           dataDir: URL(fileURLWithPath: args[i + 1])) else { exit(1) }
            print("root=\(root.path)")
            print("bundled=\(engine.isBundled)")
            print("panes=\(Pane.available(isBundled: engine.isBundled).map(\.rawValue).joined(separator: ","))")
            return
        }
        if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
            let url = URL(fileURLWithPath: args[i + 1])
            if let j = args.firstIndex(of: "--levi") {
                guard j + 1 < args.count, let variant = LeviIconVariant(rawValue: args[j + 1]) else {
                    print("--levi needs a, b, or c")
                    exit(1)
                }
                do {
                    try MainActor.assumeIsolated { try Renders.leviIcon(variant, to: url) }
                } catch {
                    print("icon render failed: \(error.localizedDescription)")
                    exit(1)
                }
            } else {
                MainActor.assumeIsolated { Renders.icon(to: url) }
            }
            return
        }
        if let i = args.firstIndex(of: "--render-guide") {
            guard i + 1 < args.count else {
                print("--render-guide needs a file")
                exit(1)
            }
            do {
                try MainActor.assumeIsolated { try Renders.guide(to: URL(fileURLWithPath: args[i + 1])) }
            } catch {
                print("guide render failed: \(error.localizedDescription)")
                exit(1)
            }
            return
        }
        if let i = args.firstIndex(of: "--render-levi") {
            guard i + 1 < args.count else {
                print("--render-levi needs a render folder")
                exit(1)
            }
            do {
                try MainActor.assumeIsolated { try Renders.levi(into: URL(fileURLWithPath: args[i + 1])) }
            } catch {
                print("Levi render failed: \(error.localizedDescription)")
                exit(1)
            }
            return
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            MainActor.assumeIsolated { Renders.run(into: URL(fileURLWithPath: args[i + 1]), args: args) }
            return
        }
        MacCleanerApp.main()
    }
}

struct MacCleanerApp: App {
    @StateObject private var model: AppModel
    @StateObject private var updates: UpdatesModel
    @StateObject private var appUpdates: AppUpdateModel
    @StateObject private var health = HealthReader()

    init() {
        let engine = Engine.locateRoot().flatMap { try? Engine(root: $0) }
        _model = StateObject(wrappedValue: AppModel(engine: engine))
        _updates = StateObject(wrappedValue: UpdatesModel(engine: engine))
        _appUpdates = StateObject(wrappedValue: AppUpdateModel(bundled: engine?.isBundled == true))
    }

    var body: some Scene {
        WindowGroup("Captain Levi", id: "main") {
            // No .frame around ContentView: a frame around the whole NavigationSplitView leaves the
            // window blank on macOS 26. The minimum size lives on the detail pane.
            ContentView(model: model, updates: updates, appUpdates: appUpdates)
                .task { await updates.checkIfDue() }
                .task { await SelfCheck.runIfAsked() }
        }
        .defaultSize(width: 1120, height: 760)
        MenuBarExtra {
            MenuBarContent(model: model, health: health)
        } label: {
            Image(systemName: "sparkles")
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar card, live: the Mac's health, and a button that opens the window on the Clean pane and starts a look.
struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var health: HealthReader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarView(health: withLastLook(health.health), lookToClean: lookToClean, openApp: showWindow)
            .onAppear { health.start() }
    }

    /// The number in the suggestion is what the last look found, when there was one.
    private func withLastLook(_ value: MenuBarHealth) -> MenuBarHealth {
        var copy = value
        if let plan = model.plan { copy.reclaimable = plan.selectedBytes }
        return copy
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Captain Levi" && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private func lookToClean() {
        model.requestedPane = .clean
        showWindow()
        if case .idle = model.state { Task { await model.scan() } }
    }
}

/// `MAC_CLEANER_SELFCHECK=FILE` draws the running app's own window into FILE (in-process, no screen capture), then quits.
enum SelfCheck {
    @MainActor
    static func runIfAsked() async {
        guard let path = ProcessInfo.processInfo.environment["MAC_CLEANER_SELFCHECK"] else { return }
        try? await Task.sleep(for: .seconds(3))
        if let window = NSApp.windows.first(where: { $0.title == "Captain Levi" && $0.isVisible }) {
            do { try MockRenderer.snapshot(of: window, to: URL(fileURLWithPath: path)) } catch { print("selfcheck failed: \(error)") }
        } else {
            print("selfcheck: no visible window")
        }
        NSApp.terminate(nil)
    }
}

/// The app icon: a plain mark of its own (Mole's name and icon belong to Mole), 1024 px.
struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.45, blue: 0.95), Color(red: 0.07, green: 0.24, blue: 0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            Image(systemName: "sparkles")
                .font(.system(size: 430, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Pictures of screens for checking the look, drawn in-process (never a screen or window capture).
/// `--render DIR` draws the illustrative screens; add `--plan FILE --home DIR` to draw a real plan.
@MainActor
enum Renders {
    static func leviIcon(_ variant: LeviIconVariant, to url: URL) throws {
        try MockRenderer.artwork(IconVariantView(variant: variant, size: 1024),
                                 size: CGSize(width: 1024, height: 1024), dark: true, to: url)
    }

    static func guide(to url: URL) throws {
        _ = ActiveLookApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try MockRenderer.artwork(FirstOpenGuide(), size: CGSize(width: 1600, height: 1000), dark: false, to: url)
    }

    /// Static approval pictures only: no engine, live health reads, or update checks.
    static func levi(into dir: URL) throws {
        _ = ActiveLookApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 1120, height: 830)
        let model = AppModel(engine: nil)
        let updates = UpdatesModel(engine: nil)
        for fixture in AppUpdateState.fixtures {
            try MockRenderer.render(
                ContentView(model: model, updates: updates, pane: .appUpdates, appUpdateFixture: fixture.state),
                size: size, dark: true, to: dir.appendingPathComponent("levi-updates-\(fixture.name).png"),
                pixelSize: size)
        }
        try MockRenderer.render(
            ContentView(model: model, updates: updates, pane: .appUpdates, appUpdateFixture: .available),
            size: size, dark: false, to: dir.appendingPathComponent("levi-updates-available-light.png"),
            pixelSize: size)
        for dark in [false, true] {
            try MockRenderer.artwork(FirstOpenGuide(), size: CGSize(width: 1600, height: 1000), dark: dark,
                                     to: dir.appendingPathComponent("first-open-guide-\(dark ? "dark" : "light").png"))
        }
        for variant in LeviIconVariant.allCases {
            try MockRenderer.artwork(IconVariantView(variant: variant), size: CGSize(width: 1024, height: 1024), dark: true,
                                     to: dir.appendingPathComponent("icon-\(variant.rawValue).png"))
        }
        try MockRenderer.artwork(IconContactSheet(), size: CGSize(width: 1600, height: 1600), dark: true,
                                 to: dir.appendingPathComponent("icons.png"))
        print("rendered 12 Levi pictures into \(dir.path)")
    }

    static func icon(to url: URL) {
        let renderer = ImageRenderer(content: AppIcon())
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("icon render failed")
            return
        }
        try? png.write(to: url)
        print("icon written to \(url.path)")
    }

    static func run(into dir: URL, args: [String]) {
        _ = ActiveLookApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let size = CGSize(width: 1120, height: 830)
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        do {
            let model = AppModel(engine: nil)
            let updates = UpdatesModel(engine: nil)
            if let planPath = value("--projects-plan"), let home = value("--home") {
                let url = URL(fileURLWithPath: planPath)
                model.builds = Policy.projectBuilds(from: try PlanRecord.read(from: url),
                                                    meta: ProjectMeta.read(from: URL(fileURLWithPath: planPath + ".meta")), home: home)
                model.projectsState = .found
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .projects), size: size, dark: true,
                                        to: dir.appendingPathComponent("real-projects.png"))
            } else if let planPath = value("--plan"), let home = value("--home") {
                let records = try PlanRecord.read(from: URL(fileURLWithPath: planPath))
                model.plan = CleanPlan(groups: Policy.groups(from: records, home: home), scannedAt: Date(),
                                       diskFreeBytes: 38_000_000_000, diskTotalBytes: 494_000_000_000)
                model.state = .reviewing
                try MockRenderer.render(ContentView(model: model, updates: updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("real-plan.png"))
            } else {
                try MockRenderer.render(ContentView(model: model, updates: updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("start.png"))
                model.plan = Fixtures.plan
                model.state = .reviewing
                try MockRenderer.render(ContentView(model: model, updates: updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("review.png"))
                try MockRenderer.render(ConfirmSheet(plan: Fixtures.plan), size: CGSize(width: 460, height: 430), dark: true,
                                        to: dir.appendingPathComponent("confirm.png"))
                model.scanProgress = Fixtures.scanProgress
                model.state = .scanning("Developer tools")
                try MockRenderer.render(ContentView(model: model, updates: updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("scanning.png"))
                model.cleanProgress = Fixtures.cleanProgress
                model.state = .cleaning
                try MockRenderer.render(ContentView(model: model, updates: updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("cleaning.png"))
                try MockRenderer.render(SuccessHeader(freed: 12_300_000_000).padding(40), size: CGSize(width: 520, height: 140), dark: true,
                                        to: dir.appendingPathComponent("done-header.png"))
                model.state = .done(freed: 12_300_000_000, cleaned: 46,
                                    skipped: [ApplyResult(status: "skipped", bytes: 820_000_000,
                                                          path: "/home/example/Library/Caches/com.figma.Desktop",
                                                          reason: "its app may be running")])
                try MockRenderer.render(ContentView(model: model, updates: updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("done.png"))
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .projects), size: size, dark: true,
                                        to: dir.appendingPathComponent("projects-start.png"))
                model.projectsProgress = Fixtures.projectsLook
                model.projectsState = .looking("Sites")
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .projects), size: size, dark: true,
                                        to: dir.appendingPathComponent("projects-looking.png"))
                model.builds = Fixtures.builds
                model.projectsState = .found
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .projects), size: size, dark: true,
                                        to: dir.appendingPathComponent("projects.png"))
                try MockRenderer.render(ProjectsConfirmSheet(ticked: Fixtures.builds.filter(\.selected)),
                                        size: CGSize(width: 460, height: 300), dark: true,
                                        to: dir.appendingPathComponent("projects-confirm.png"))
                let fake = Fixtures.updateReport
                updates.report = fake.0
                updates.allPlan = fake.1
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("updates-all.png"))
                updates.allProgress = (3, 5)
                updates.busy = "Taking the safe changes and running the safety tests…"
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .updates), size: size, dark: true,
                                        to: dir.appendingPathComponent("updates-all-running.png"))
                updates.allProgress = nil
                updates.busy = nil
                let un = model.uninstall
                un.apps = Fixtures.installedApps
                un.chosen = Fixtures.installedApps[0]
                un.leftovers = Fixtures.leftovers
                un.needsAdmin = ["/Library/LaunchDaemons/com.tinyspeck.slackmacgap.plist"]
                for (name, stage) in [("uninstall-list", UninstallModel.Stage.list), ("uninstall-review", .review), ("uninstall-done", .done)] {
                    un.stage = stage
                    if stage == .done {
                        un.moved = Fixtures.leftovers.filter(\.selected).map { ApplyResult(status: "trashed", bytes: $0.bytes, path: $0.path, reason: "") }
                        un.check = UninstallCheck(left: [], nameOnly: ["\(Fixtures.home)/Library/Application Support/Slack Helper Tools"], uninspected: [], incomplete: false)
                    }
                    if stage == .done {
                        try MockRenderer.render(UninstallView(model: un, flat: true).frame(width: 860, height: 700),
                                                size: CGSize(width: 860, height: 700), dark: true, to: dir.appendingPathComponent("\(name).png"))
                        continue
                    }
                    try MockRenderer.render(ContentView(model: model, updates: updates, pane: .uninstall), size: size, dark: true,
                                            to: dir.appendingPathComponent("\(name).png"))
                }
                try MockRenderer.render(MenuBarView(health: Fixtures.health), size: CGSize(width: 360, height: 560), dark: true,
                                        to: dir.appendingPathComponent("menubar.png"))
                let reader = HealthReader()
                reader.refresh()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                reader.refresh()
                try MockRenderer.render(MenuBarView(health: reader.health), size: CGSize(width: 360, height: 560), dark: true,
                                        to: dir.appendingPathComponent("menubar-live.png"))
                print("live health: \(reader.health)")
                try MockRenderer.render(MenuBarView(health: Fixtures.health), size: CGSize(width: 360, height: 560), dark: false,
                                        to: dir.appendingPathComponent("menubar-light.png"))
                updates.allResult = "Took 5 changes. 3 stay for your look."
                try MockRenderer.render(ContentView(model: model, updates: updates, pane: .updates), size: size, dark: false,
                                        to: dir.appendingPathComponent("updates-all-done-light.png"))
            }
            print("rendered into \(dir.path)")
        } catch {
            print("render failed: \(error.localizedDescription)")
        }
    }
}
