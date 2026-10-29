import Foundation

// Small value types for what the working screens show while a scan or a clean runs. AppModel fills them from the
// plan file (growing during a dry run) and the history file (growing during a clean); the renders set them directly.

/// What a running dry run has found so far, built from the plan records as clean.sh appends them.
struct ScanProgress: Equatable {
    struct Section: Identifiable, Equatable {
        var id: String
        /// The section name bin/clean.sh uses, which its "➤" lines repeat.
        var raw: String
        var title: String
        var symbol: String
        var bytes: Int64 = 0
        var count = 0
        var finished = false
    }

    var startedAt = Date()
    var sections: [Section] = []
    /// The section a "➤" line named last: the one being scanned now.
    var active: String?
    /// Sections the scan has moved past.
    var passed: Set<String> = []
    var bytes: Int64 = 0
    var items = 0
    var latestPath: String?

    var activeTitle: String? {
        guard let active else { return nil }
        return Policy.specs[active]?.title ?? active
    }

    /// Adds newly found records. Counted like Policy.groups does: nothing covered by an ancestor that is in the plan
    /// too, nothing outside the home folder.
    mutating func add(_ records: [PlanRecord], home: String) {
        for record in records where record.coveredBy.isEmpty && record.path.hasPrefix(home + "/") {
            let isTrash = record.path.hasPrefix(home + "/.Trash/")
            let key = isTrash ? Policy.trashGroupID : record.section
            let spec = isTrash ? Policy.trashSpec : (Policy.specs[record.section]
                ?? Policy.GroupSpec(title: record.section, symbol: "folder", detail: "", order: 50))
            let index: Int
            if let found = sections.firstIndex(where: { $0.id == key }) {
                index = found
            } else {
                sections.append(Section(id: key, raw: record.section, title: spec.title, symbol: spec.symbol))
                index = sections.count - 1
            }
            sections[index].bytes += record.kb * 1024
            sections[index].count += 1
            bytes += record.kb * 1024
            items += 1
            latestPath = record.path
        }
        refreshFinished()
    }

    /// A "➤ Section" line arrived: the scan moved on, so the section before it is done.
    mutating func setActive(_ name: String) {
        if let active, active != name { passed.insert(active) }
        active = name
        refreshFinished()
    }

    private mutating func refreshFinished() {
        for i in sections.indices {
            sections[i].finished = passed.contains(sections[i].raw) && sections[i].raw != active
        }
    }
}

/// How far a clean (or a move to the Trash, or a project delete) has got, from apply.sh's history lines.
struct CleanProgress: Equatable {
    var startedAt = Date()
    /// Ticked paths handed to apply.sh.
    var total = 0
    /// Items apply.sh has dealt with, removed or left alone.
    var processed = 0
    var leftAlone = 0
    var freedBytes: Int64 = 0
    var latestPath: String?

    var fraction: Double { total > 0 ? min(1, Double(processed) / Double(total)) : 0 }

    /// Seconds still to go, a rough guess from the pace so far; nil until enough items are done to say.
    func secondsLeft(now: Date = Date()) -> TimeInterval? {
        let elapsed = now.timeIntervalSince(startedAt)
        guard processed >= 25, elapsed >= 8, processed < total else { return nil }
        return elapsed / Double(processed) * Double(total - processed)
    }

    /// Takes in history lines (time, result, KB, path, reason, tab-separated).
    mutating func add(lines: [String]) {
        for line in lines {
            let f = line.components(separatedBy: "\t")
            guard f.count >= 4 else { continue }
            processed += 1
            if f[1] == "deleted" || f[1] == "trashed" {
                freedBytes += (Int64(f[2]) ?? 0) * 1024
            } else {
                leftAlone += 1
            }
            latestPath = f[3]
        }
    }
}

/// The folders bin/projects.sh has looked through so far ("➤ Looking in NAME" lines).
struct ProjectsLookProgress: Equatable {
    var startedAt = Date()
    var finished: [String] = []
    var current: String?

    mutating func look(in name: String) {
        if let current, current != name { finished.append(current) }
        current = name
    }
}

/// Reads the lines a growing file has gained since a byte offset (the history file during a clean).
enum FileTail {
    static func size(of url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    /// New complete lines after `offset`, and the offset to ask from next time. A half-written last line waits.
    static func newLines(from url: URL, offset: Int) -> (lines: [String], offset: Int) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ([], offset) }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return ([], offset) }
        let size = Int(end)
        let start = size < offset ? 0 : offset
        guard size > start else { return ([], start) }
        do {
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.readToEnd() ?? Data()
            guard let last = data.lastIndex(of: 10) else { return ([], start) }
            let complete = data[data.startIndex...last]
            let lines = String(decoding: complete, as: UTF8.self).split(separator: "\n").map(String.init)
            return (lines, start + complete.count)
        } catch {
            return ([], start)
        }
    }
}

enum Elapsed {
    /// "0:42", "12:05", "1:02:30".
    static func text(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "about 22 min left", "less than a minute left".
    static func left(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 90 { return "about \(minutes) min left" }
        return "about \(String(format: "%.1f", seconds / 3600)) hours left"
    }
}
