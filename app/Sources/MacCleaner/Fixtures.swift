import Foundation

/// Illustrative data for renders of the look only. Real numbers come from a dry run.
enum Fixtures {
    static let MB: Int64 = 1_000_000
    static let home = NSHomeDirectory()

    static var plan: CleanPlan {
        let scanned = Calendar.current.date(bySettingHour: 15, minute: 52, second: 0, of: Date()) ?? Date()
        var groups = [
            CleanGroup(id: "User essentials", title: "Caches and logs", symbol: "square.stack.3d.up",
                       detail: "Your Library's caches and logs. Apps rebuild these.",
                       items: [CleanItem(path: "\(home)/Library/Caches/com.spotify.client", bytes: 1_900 * MB),
                               CleanItem(path: "\(home)/Library/Caches/com.tinyspeck.slackmacgap", bytes: 640 * MB),
                               CleanItem(path: "\(home)/Library/Caches/us.zoom.xos", bytes: 410 * MB),
                               CleanItem(path: "\(home)/Library/Logs/DiagnosticReports", bytes: 220 * MB)]
                           + (1...37).map { CleanItem(path: "\(home)/Library/Caches/com.example.app\($0)", bytes: 33 * MB) },
                       expanded: true),
            CleanGroup(id: "Browsers", title: "Browsers", symbol: "globe", detail: "Page caches only. History, cookies and logins stay.",
                       items: [CleanItem(path: "\(home)/Library/Caches/Arc/Cache", bytes: 2_100 * MB),
                               CleanItem(path: "\(home)/Library/Caches/Google/Chrome/Default/Code Cache", bytes: 640 * MB)]),
            CleanGroup(id: "Developer tools", title: "Developer tools", symbol: "hammer",
                       detail: "Package and build caches from your developer tools.",
                       items: [CleanItem(path: "\(home)/.npm/_cacache", bytes: 1_600 * MB),
                               CleanItem(path: "\(home)/Library/Caches/Homebrew", bytes: 1_200 * MB),
                               CleanItem(path: "\(home)/Library/Caches/ms-playwright", bytes: 1_400 * MB)]),
            CleanGroup(id: "trash", title: "Trash", symbol: "trash", detail: "What you put in the Trash. Emptying it cannot be undone.",
                       caution: .yourFiles, items: [CleanItem(path: "\(home)/.Trash/old.zip", bytes: 2_300 * MB, selected: false)]),
            CleanGroup(id: "App leftovers", title: "Leftovers from deleted apps", symbol: "shippingbox",
                       detail: "Data from apps removed over 30 days ago. Look before you tick.", caution: .yourFiles,
                       items: [CleanItem(path: "\(home)/Library/Application Support/Loom", bytes: 820 * MB, selected: false)]),
        ]
        groups[0].showAll = false
        return CleanPlan(groups: groups, scannedAt: scanned, diskFreeBytes: 38_000 * MB, diskTotalBytes: 494_000 * MB)
    }

    /// A dry run part-way through: four sections found so far, the fourth still being scanned.
    static var scanProgress: ScanProgress {
        var p = ScanProgress(startedAt: Date().addingTimeInterval(-87))
        func section(_ raw: String, _ items: Int, _ mb: Int64) {
            let spec = Policy.specs[raw]!
            p.sections.append(.init(id: raw, raw: raw, title: spec.title, symbol: spec.symbol, bytes: mb * MB, count: items))
            p.items += items
            p.bytes += mb * MB
        }
        section("User essentials", 212, 1_950)
        section("App caches", 38, 640)
        section("Browsers", 96, 820)
        section("Developer tools", 143, 410)
        p.passed = ["User essentials", "App caches", "Browsers"]
        p.active = "Developer tools"
        for i in p.sections.indices { p.sections[i].finished = p.passed.contains(p.sections[i].raw) }
        p.latestPath = "\(home)/Library/Caches/ms-playwright/chromium-1140/chrome-mac/Chromium.app/Contents/Frameworks"
        return p
    }

    /// A clean about a quarter of the way through 11,097 ticked items.
    static var cleanProgress: CleanProgress {
        CleanProgress(startedAt: Date().addingTimeInterval(-14 * 60), total: 11_097, processed: 3_120, leftAlone: 12,
                      freedBytes: 4_200 * MB,
                      latestPath: "\(home)/Library/Caches/com.example.app31/Cache/Cache_Data/f_00a3c1")
    }

    /// The look for project folders, three folders done and the fourth in hand.
    static var projectsLook: ProjectsLookProgress {
        ProjectsLookProgress(startedAt: Date().addingTimeInterval(-23), finished: ["Developer", "Projects", "Code"], current: "Sites")
    }

    /// Build folders as the Project folders pane shows them (invented names, for renders of the look only).
    static var builds: [ProjectBuild] {
        func days(_ n: Double) -> Date { Date().addingTimeInterval(-n * 86_400) }
        func build(_ project: String, _ name: String, _ mb: Int64, _ state: ProjectMeta.State, _ ago: Double, tick: Bool) -> ProjectBuild {
            ProjectBuild(path: "\(home)/\(project)/\(name)", project: "\(home)/\(project)", bytes: mb * MB, sizeKnown: true,
                         lastChange: days(ago), state: state, selected: tick)
        }
        return [
            build("shop-site", "node_modules", 1_240, .old, 74, tick: true),
            build("shop-site", ".next", 310, .old, 74, tick: true),
            build("old-api", "node_modules", 860, .old, 190, tick: true),
            build("old-api", "dist", 12, .old, 190, tick: false),
            build("mobile-app", ".build", 2_100, .old, 41, tick: true),
            build("mobile-app", "Pods", 420, .old, 41, tick: true),
            build("dashboard", "node_modules", 980, .recent, 2, tick: false),
            build("portal", "node_modules", 1_450, .running, 1, tick: false),
            build("rust-tool", "target", 3_800, .old, 29, tick: true),
        ]
    }

    /// A made-up update report for renders of the Updates pane.
    static var updateReport: (UpdateReport, UpdateAllPlan) {
        func c(_ n: Int, _ verdict: String, _ subject: String, _ summary: String, _ reasons: [String] = []) -> UpdateReport.Commit {
            UpdateReport.Commit(sha: String(format: "%040d", n), short: String(format: "%07d", n), date: "2026-10-\(10 + n % 12)T09:00:00Z",
                                subject: subject, summary: summary, verdict: verdict, reasons: reasons, flags: [], files: [])
        }
        let commits = [
            c(1, "take", "fix(status): show the right battery cycle count", "Fixes a problem in the system status view: show the right battery cycle count."),
            c(2, "take", "perf: speed up scanning of large cache folders", "Speeds up the clean scan (what Captain Levi finds to delete): scanning of large cache folders."),
            c(3, "take", "docs: explain the dry run better", "Updates the documentation."),
            c(4, "take", "fix(analyze): keep the cursor on the folder after a refresh", "Fixes a problem in the disk space viewer (analyze): keep the cursor on the folder after a refresh."),
            c(5, "take", "refactor: share one size formatter", "Rearranges code in shared code the cleaner relies on (no change meant): share one size formatter."),
            c(6, "take", "fix: clean scan skips a cache it just listed", "Fixes a problem in the clean scan (what Captain Levi finds to delete): skips a cache it just listed."),
            c(7, "review", "feat: clean Zed's old extension caches", "Adds something new to the clean scan: Zed's old extension caches.", ["deletes files or adds new places to delete (2 lines)"]),
            c(8, "skip", "chore: release 1.9.2", "Nothing changes for you: it only touches upstream's own build, release and contributor files (release 1.9.2)."),
        ]
        var plan = UpdateAllPlan(eligible: commits.filter { $0.verdict == "take" }.map(\.sha).dropLast(1).map { $0 }, left: [:])
        plan.left[commits[5].sha] = "touches_your_changes"
        return (UpdateReport(checked_at: ISO8601DateFormatter().string(from: Date()), upstream_head: nil, fetch_ok: true, fetch_error: nil,
                             commits: commits), plan)
    }
}
