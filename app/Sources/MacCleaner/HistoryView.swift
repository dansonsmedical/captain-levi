import SwiftUI

/// Every item the app has removed or left alone, newest first, from apply.sh's history file.
struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section {
                if model.history.isEmpty {
                    Text("Nothing has been cleaned yet.").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach(model.history) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.time.replacingOccurrences(of: "T", with: " "))
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(label(for: entry.status))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(entry.status == "skipped" ? .secondary : .primary)
                            .frame(width: 110, alignment: .leading)
                        Text(entry.path.abbreviatingHome(model.home))
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .help(entry.path)
                        Spacer(minLength: 12)
                        Text(entry.status == "skipped" ? entry.reason : Bytes.short(entry.bytes))
                            .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("History").font(.system(size: 30, weight: .bold)).textCase(nil).padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
        .toolbar(removing: .title)
    }

    private func label(for status: String) -> String {
        switch status {
        case "deleted": "Removed"
        case "trashed": "Moved to Trash"
        case "skipped": "Left alone"
        default: status
        }
    }
}
