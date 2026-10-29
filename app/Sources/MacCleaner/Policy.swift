import Foundation

/// How a dry-run plan becomes what the user sees: Mole's sections as groups with plain names, plain caches ticked,
/// anything of the user's unticked and flagged, and nothing outside the user's home folder (apply.sh refuses those anyway).
enum Policy {
    struct GroupSpec {
        var title: String
        var symbol: String
        var detail: String
        var caution: Caution = .none
        var ticked = true
        var order: Int
    }

    static let trashGroupID = "trash"

    /// Keyed by the section names bin/clean.sh uses.
    static let specs: [String: GroupSpec] = [
        "User essentials": GroupSpec(title: "Caches and logs", symbol: "square.stack.3d.up",
                                     detail: "Your Library's caches and logs. Apps rebuild these.", order: 1),
        "App caches": GroupSpec(title: "App caches", symbol: "app.badge",
                                detail: "Caches kept inside apps' own folders.", order: 2),
        "Browsers": GroupSpec(title: "Browsers", symbol: "globe",
                              detail: "Page caches only. History, cookies and logins stay.", order: 3),
        "Developer tools": GroupSpec(title: "Developer tools", symbol: "hammer",
                                     detail: "Package and build caches from your developer tools.", order: 4),
        "Cloud & Office": GroupSpec(title: "Cloud & Office", symbol: "icloud",
                                    detail: "Google Drive, Dropbox and Office caches. Your documents stay.", order: 5),
        "Apps & utilities": GroupSpec(title: "Apps & utilities", symbol: "square.grid.2x2",
                                      detail: "Caches from other apps you use.", order: 6),
        "Virtualization": GroupSpec(title: "Virtual machine tools", symbol: "cube",
                                    detail: "Caches from VM tools. Your virtual machines stay.", order: 7),
        "Application Support": GroupSpec(title: "App support caches", symbol: "folder",
                                         detail: "Cache folders inside Application Support.", order: 8),
        "Apple Silicon updates": GroupSpec(title: "Rosetta updates", symbol: "cpu",
                                           detail: "Leftover Rosetta update files.", order: 9),
        "Device backups & firmware": GroupSpec(title: "iPhone and iPad updates", symbol: "iphone",
                                               detail: "Downloaded device software updates. They can be downloaded again.",
                                               ticked: false, order: 10),
        "App leftovers": GroupSpec(title: "Leftovers from deleted apps", symbol: "shippingbox",
                                   detail: "Data from apps removed over 30 days ago. Look before you tick.",
                                   caution: .yourFiles, ticked: false, order: 11),
    ]

    static let trashSpec = GroupSpec(title: "Trash", symbol: "trash",
                                     detail: "What you put in the Trash. Emptying it cannot be undone.",
                                     caution: .yourFiles, ticked: false, order: 12)

    static func groups(from records: [PlanRecord], home: String) -> [CleanGroup] {
        var buckets: [String: (spec: GroupSpec, items: [CleanItem])] = [:]
        for record in records {
            // Counted under an ancestor that is in the plan too, or outside the home folder.
            guard record.coveredBy.isEmpty, record.path.hasPrefix(home + "/") else { continue }
            let isTrash = record.path.hasPrefix(home + "/.Trash/")
            let key = isTrash ? trashGroupID : record.section
            let spec = isTrash ? trashSpec : (specs[record.section] ?? GroupSpec(
                title: record.section, symbol: "folder", detail: "Found by the dry run.", ticked: false, order: 50))
            var item = CleanItem(path: record.path, bytes: record.kb * 1024, count: max(1, record.count),
                                 selected: spec.ticked)
            if record.path.contains("/Service Worker/") {
                item.selected = false
                item.note = "Offline data for websites"
            }
            buckets[key, default: (spec, [])].items.append(item)
        }
        return buckets
            .sorted { $0.value.spec.order == $1.value.spec.order ? $0.key < $1.key : $0.value.spec.order < $1.value.spec.order }
            .map { key, bucket in
                CleanGroup(id: key, title: bucket.spec.title, symbol: bucket.spec.symbol, detail: bucket.spec.detail,
                           caution: bucket.spec.caution, items: bucket.items.sorted { $0.bytes > $1.bytes })
            }
    }
}
