import Foundation

/// What bin/projects.sh wrote beside its plan (PLAN.meta, five NUL-separated fields per folder). Display only:
/// apply.sh never trusts it, and a folder without a record here is shown as unchecked and left unticked.
struct ProjectMeta: Hashable {
    enum State: String { case old, recent, running, unverified }
    var path: String
    var lastChange: Date?
    var state: State?
    var project: String
    var suggestTick: Bool

    static func read(from url: URL) -> [String: ProjectMeta] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var result: [String: ProjectMeta] = [:]
        var i = 0
        while i + 4 < fields.count {
            let epoch = TimeInterval(fields[i + 1]) ?? 0
            result[fields[i]] = ProjectMeta(path: fields[i], lastChange: epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil,
                                            state: State(rawValue: fields[i + 2]), project: fields[i + 3],
                                            suggestTick: fields[i + 4] == "yes")
            i += 5
        }
        return result
    }
}

/// One old build folder (node_modules, target, .venv, ...) found inside a project folder.
struct ProjectBuild: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var project: String
    var bytes: Int64
    var sizeKnown: Bool
    var lastChange: Date?
    var state: ProjectMeta.State?
    var selected: Bool

    var name: String { (path as NSString).lastPathComponent }
    /// A program runs in the project, or the scan could not tell: it cannot be ticked.
    var canTick: Bool { state == .old || state == .recent }
    var isRecent: Bool { state == .recent }

    /// "last changed 23 days ago", or the reason it is held back.
    func ageText(now: Date = Date()) -> String {
        switch state {
        case .running: return "running now"
        case .recent: return "in use lately"
        case .unverified: return "couldn't check"
        case .old, nil:
            guard let lastChange else { return "age unknown" }
            let days = Int(now.timeIntervalSince(lastChange) / 86_400)
            switch days {
            case ..<1: return "last changed today"
            case 1: return "last changed yesterday"
            case 2..<60: return "last changed \(days) days ago"
            case 60..<730: return "last changed \(days / 30) months ago"
            default: return "last changed \(days / 365) years ago"
            }
        }
    }

    /// Why a generic name starts unticked, when nothing else holds it back.
    var note: String? {
        guard state == .old, !selected else { return nil }
        return "may hold files you made"
    }
}

extension Policy {
    /// The plan's "Project folders" records joined with their display-only meta. Ticked: old, size known, a specific
    /// build-folder name whose manifest sits beside it (the script decides). Everything else starts unticked.
    static func projectBuilds(from records: [PlanRecord], meta: [String: ProjectMeta], home: String) -> [ProjectBuild] {
        records.compactMap { record -> ProjectBuild? in
            guard record.section == "Project folders", record.path.hasPrefix(home + "/") else { return nil }
            let info = meta[record.path]
            let tick = (info?.suggestTick ?? false) && info?.state == .old && record.sizeKnown
            let project = info?.project.isEmpty == false ? info!.project : (record.path as NSString).deletingLastPathComponent
            return ProjectBuild(path: record.path, project: project, bytes: record.kb * 1024, sizeKnown: record.sizeKnown,
                                lastChange: info?.lastChange, state: info?.state, selected: tick)
        }
        .sorted { $0.bytes > $1.bytes }
    }
}
