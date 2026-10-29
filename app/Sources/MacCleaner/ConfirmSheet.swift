import SwiftUI

/// The last stop before anything is deleted: what goes, for good, and the one red button.
struct ConfirmSheet: View {
    let plan: CleanPlan
    var onCancel: () -> Void = {}
    var onConfirm: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(Bytes.short(plan.selectedBytes))?")
                .font(.title2.bold())
            Text("These are removed for good, not moved to the Trash. Apps rebuild their caches as they need them. Each path is written to History.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(plan.groups.filter(\.isSelected)) { group in
                    HStack {
                        Image(systemName: group.symbol).foregroundStyle(.secondary).frame(width: 20)
                        Text(group.title)
                        Spacer()
                        Text(Bytes.short(group.selectedBytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    Divider().padding(.leading, 44)
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))

            let skipped = plan.groups.reduce(0) { $0 + $1.skippedCount }
            if skipped > 0 {
                Label("\(skipped) item left alone because its app is open.", systemImage: "pause.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button(role: .destructive, action: onConfirm) {
                    Text("Delete \(Bytes.short(plan.selectedBytes))").monospacedDigit()
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
