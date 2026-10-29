import Foundation

/// One record of the plan that `bin/clean.sh --plan-out` writes (NUL-separated, six fields).
struct PlanRecord: Hashable {
    var section: String
    var path: String
    var kb: Int64
    var count: Int
    var sizeKnown: Bool
    var coveredBy: String

    static func read(from url: URL) throws -> [PlanRecord] {
        let data = try Data(contentsOf: url)
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var records: [PlanRecord] = []
        var i = 0
        while i + 5 < fields.count {
            records.append(PlanRecord(section: fields[i], path: fields[i + 1], kb: Int64(fields[i + 2]) ?? 0,
                                      count: Int(fields[i + 3]) ?? 1, sizeKnown: fields[i + 4] == "true",
                                      coveredBy: fields[i + 5]))
            i += 6
        }
        return records
    }

    /// Reads the complete records in `data`; `consumed` is the byte count they cover. A record still being written
    /// (fewer than six NUL-terminated fields) is left for the next read.
    static func parse(_ data: Data) -> (records: [PlanRecord], consumed: Int) {
        var records: [PlanRecord] = []
        var fields: [String] = []
        var fieldStart = 0
        var consumed = 0
        var index = 0
        for byte in data {
            if byte == 0 {
                fields.append(String(decoding: data[(data.startIndex + fieldStart)..<(data.startIndex + index)], as: UTF8.self))
                fieldStart = index + 1
                if fields.count == 6 {
                    records.append(PlanRecord(section: fields[0], path: fields[1], kb: Int64(fields[2]) ?? 0,
                                              count: Int(fields[3]) ?? 1, sizeKnown: fields[4] == "true",
                                              coveredBy: fields[5]))
                    fields.removeAll(keepingCapacity: true)
                    consumed = index + 1
                }
            }
            index += 1
        }
        return (records, consumed)
    }

    /// The records written after byte `offset` of a plan that is still growing (clean.sh appends as it scans), and the
    /// offset to ask from next time. Only complete records are returned. A file that has shrunk (a new scan began)
    /// is read again from the start; a missing file gives nothing.
    static func readNew(from url: URL, offset: Int) -> (records: [PlanRecord], offset: Int) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ([], offset) }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return ([], offset) }
        let size = Int(end)
        let start = size < offset ? 0 : offset
        guard size > start else { return ([], start) }
        do {
            try handle.seek(toOffset: UInt64(start))
            let data = try handle.readToEnd() ?? Data()
            let parsed = parse(data)
            return (parsed.records, start + parsed.consumed)
        } catch {
            return ([], start)
        }
    }

    static func write(_ records: [PlanRecord], to url: URL) throws {
        var data = Data()
        for r in records {
            for field in [r.section, r.path, String(r.kb), String(r.count), r.sizeKnown ? "true" : "false", r.coveredBy] {
                data.append(contentsOf: Array(field.utf8))
                data.append(0)
            }
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// One thing the cleaner would remove, as reported by a dry run.
struct CleanItem: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var bytes: Int64
    var count = 1
    var selected = true
    /// Set when the item is found but left alone (for example its app is open).
    var skippedReason: String?
    /// A short warning shown next to the path, for items that are not plain caches.
    var note: String?
}

/// Why a group needs a second look before it is cleaned.
enum Caution: Hashable {
    case none
    case needsPassword   // runs with administrator rights; macOS asks for the Mac password
    case yourFiles       // not a cache: something the user made or kept; never ticked for the user
}

/// A section of the clean, as Mole groups it (App caches, Browsers, Developer tools, ...).
struct CleanGroup: Identifiable, Hashable {
    let id: String
    var title: String
    var symbol: String
    var detail: String
    var caution: Caution = .none
    var items: [CleanItem]
    var expanded = false
    var showAll = false

    static let previewCount = 4

    var bytes: Int64 { items.filter { $0.skippedReason == nil }.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { items.filter { $0.selected && $0.skippedReason == nil }.reduce(0) { $0 + $1.bytes } }
    var isSelected: Bool { items.contains { $0.selected && $0.skippedReason == nil } }
    var skippedCount: Int { items.filter { $0.skippedReason != nil }.count }
    var itemCount: Int { items.reduce(0) { $0 + $1.count } }
    var hiddenCount: Int { showAll ? 0 : max(0, items.count - Self.previewCount) }
    var hiddenBytes: Int64 { showAll ? 0 : items.dropFirst(Self.previewCount).reduce(0) { $0 + $1.bytes } }
    var visibleIndices: Range<Int> { 0..<(showAll ? items.count : min(items.count, Self.previewCount)) }
}

/// The result of one dry run.
struct CleanPlan {
    var groups: [CleanGroup]
    var scannedAt: Date
    var diskFreeBytes: Int64
    var diskTotalBytes: Int64
    /// The plan file the engine wrote; apply.sh checks every ticked path against it.
    var planFile: URL?

    var foundBytes: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { groups.reduce(0) { $0 + $1.selectedBytes } }
    var selectedGroupCount: Int { groups.filter(\.isSelected).count }
    var selectedPaths: [String] {
        groups.flatMap { $0.items.filter { $0.selected && $0.skippedReason == nil }.map(\.path) }
    }
}

/// What apply.sh did with one ticked path.
struct ApplyResult: Hashable {
    var status: String   // deleted, trashed, would-delete, would-trash, skipped
    var bytes: Int64
    var path: String
    var reason: String

    var succeeded: Bool { status == "deleted" || status == "trashed" }
}

/// A line of the history apply.sh keeps.
struct HistoryEntry: Identifiable, Hashable {
    var id: String { "\(time)|\(path)|\(status)" }
    var time: String
    var status: String
    var bytes: Int64
    var path: String
    var reason: String
}

enum Bytes {
    /// For running totals: "0 MB" rather than "under 1 MB" while the number is still small.
    static func live(_ bytes: Int64) -> String { bytes < 1_000_000 ? "0 MB" : short(bytes) }

    /// Finder-style decimal sizes, kept short: "15.6 GB", "830 MB".
    static func short(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            let text = gb >= 100 ? String(format: "%.0f", gb) : String(format: "%.1f", gb)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + " GB"
        }
        let mb = Double(bytes) / 1_000_000
        return mb >= 1 ? String(format: "%.0f MB", mb) : "under 1 MB"
    }
}

extension String {
    /// The path with the home folder shown as ~, as the user sees it in Finder.
    func abbreviatingHome(_ home: String) -> String {
        hasPrefix(home + "/") ? "~" + dropFirst(home.count) : self
    }
}
