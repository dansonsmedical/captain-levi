import SwiftUI

/// A report used by the preview fixtures.
struct UpdateReport: Decodable {
    struct Flag: Decodable, Hashable {
        var kind: String?
        var file: String?
        var line: Int?
        var text: String?
    }

    struct FileChange: Decodable, Hashable {
        var path: String?
        var added: Int?
        var removed: Int?
    }

    struct Commit: Decodable, Hashable, Identifiable {
        var id: String { sha }
        var sha: String
        var short: String?
        var date: String?
        var subject: String?
        var summary: String?
        var verdict: String?
        var reasons: [String]?
        var flags: [Flag]?
        var files: [FileChange]?
    }

    var checked_at: String?
    var upstream_head: String?
    var fetch_ok: Bool?
    var fetch_error: String?
    var commits: [Commit]?
}

/// Retained display model for local previews. Public builds use Captain Levi updates.
@MainActor
final class UpdatesModel: ObservableObject {
    @Published var report: UpdateReport?
    @Published var busy: String?
    @Published var message: String?
    @Published var expanded: Set<String> = []
    @Published var allPlan: UpdateAllPlan?
    @Published var allProgress: (done: Int, total: Int)?
    @Published var allResult: String?
    let engine: Engine?
    init(engine: Engine?) { self.engine = engine }
    var commits: [UpdateReport.Commit] { report?.commits ?? [] }
    var pendingCount: Int { commits.count }
    var footer: String { "Made from Mole (GPL-3.0)" }
    func checkIfDue() async {}
    func check(fetch: Bool) async {}
    func updateAll() async {}
    func take(_ commit: UpdateReport.Commit) async {}
    func skip(_ commit: UpdateReport.Commit) async {}
}

struct UpdateAllPlan: Equatable {
    var eligible: [String]
    /// sha -> why Update all leaves it: touches_your_changes, needs_your_look, not_in_your_copy, clashes, breaks_a_test
    var left: [String: String]
}

struct UpdatesView: View {
    @ObservedObject var model: UpdatesModel
    @State private var confirmTake: UpdateReport.Commit?
    @State private var confirmAll = false

    var body: some View {
        List {
            Section {
                if let busy = model.busy, model.allProgress == nil {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(busy).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                if let message = model.message {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.callout)
                }
                if model.report == nil && model.busy == nil {
                    Text("Not checked yet.").foregroundStyle(.secondary).padding(.vertical, 6)
                }
                ForEach(model.commits) { commit in
                    row(for: commit)
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.pendingCount == 0 ? "Up to date with Mole" : "\(model.pendingCount) \(model.pendingCount == 1 ? "change" : "changes") from Mole to review")
                        .font(.system(size: 30, weight: .bold))
                    Text(subtitle).foregroundStyle(.secondary)
                    Button("Check now") { Task { await model.check(fetch: true) } }
                        .disabled(model.busy != nil)
                        .padding(.top, 4)
                    if let plan = model.allPlan, !plan.eligible.isEmpty {
                        UpdateAllCard(plan: plan, left: model.pendingCount - plan.eligible.count, progress: model.allProgress,
                                      result: model.allResult, busy: model.busy != nil, start: { confirmAll = true })
                            .padding(.top, 10)
                    } else if let result = model.allResult {
                        Label(result, systemImage: "checkmark.circle").foregroundStyle(.secondary).font(.callout).padding(.top, 8)
                    }
                }
                .textCase(nil)
                .padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
        .toolbar(removing: .title)
        .confirmationDialog("Take \(model.allPlan?.eligible.count ?? 0) safe changes from Mole?", isPresented: $confirmAll) {
            Button("Update all") { Task { await model.updateAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each one is a change that looked safe and touches nothing you built. They go in one at a time, the safety tests run after every ten, and a change that fails a test stays out. The other \(model.pendingCount - (model.allPlan?.eligible.count ?? 0)) wait for your look. Nothing is deleted from your Mac.")
        }
        .confirmationDialog("Take this change into your copy?", isPresented: Binding(
            get: { confirmTake != nil }, set: { if !$0 { confirmTake = nil } }), presenting: confirmTake) { commit in
            Button("Take it") { Task { await model.take(commit) } }
            Button("Cancel", role: .cancel) {}
        } message: { commit in
            Text("It needs your look: \((commit.reasons ?? []).prefix(3).joined(separator: "; ")). Taking it runs the safety tests with the change applied, on a throwaway test folder, and undoes it if any test fails.")
        }
    }

    private func row(for commit: UpdateReport.Commit) -> some View {
        CommitRow(commit: commit, why: model.allPlan?.left[commit.sha], expanded: model.expanded.contains(commit.sha),
                  toggle: { toggle(commit) }, take: { takeTapped(commit) },
                  skip: { Task { await model.skip(commit) } }, busy: model.busy != nil)
    }

    private func toggle(_ commit: UpdateReport.Commit) {
        if model.expanded.contains(commit.sha) {
            model.expanded.remove(commit.sha)
        } else {
            model.expanded.insert(commit.sha)
        }
    }

    /// A change that looks safe is taken at once; one that needs a look asks first.
    private func takeTapped(_ commit: UpdateReport.Commit) {
        if commit.verdict == "take" {
            Task { await model.take(commit) }
        } else {
            confirmTake = commit
        }
    }

    private var subtitle: String {
        guard let report = model.report else { return "Your copy only takes a change from Mole after a safety check and your OK." }
        var parts: [String] = []
        if let checked = report.checked_at, let date = ISO8601DateFormatter().date(from: checked) {
            parts.append("Last checked \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        if report.fetch_ok == false { parts.append("GitHub could not be reached: \(report.fetch_error ?? "unknown error")") }
        parts.append("Nothing is taken without your OK.")
        return parts.joined(separator: ". ")
    }
}

private struct CommitRow: View {
    var commit: UpdateReport.Commit
    /// Why Update all leaves this change, when it does.
    var why: String?
    var expanded: Bool
    var toggle: () -> Void
    var take: () -> Void
    var skip: () -> Void
    var busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VerdictTag(verdict: commit.verdict ?? "review", why: why)
                Text(commit.subject ?? commit.sha).font(.headline).lineLimit(2)
                Spacer(minLength: 12)
                Text(String((commit.date ?? "").prefix(10))).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(.secondary).frame(width: 16)
                }
                .buttonStyle(.plain)
            }
            if let summary = commit.summary, !summary.isEmpty {
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            if expanded {
                ForEach(commit.reasons ?? [], id: \.self) { reason in
                    Label(reason, systemImage: "smallcircle.filled.circle").font(.callout)
                }
                ForEach(commit.flags ?? [], id: \.self) { flag in
                    Text("\(flag.file ?? ""):\(flag.line ?? 0)  \(flag.text ?? "")")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                Text((commit.files ?? []).compactMap(\.path).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack(spacing: 10) {
                if commit.verdict != "skip" {
                    Button("Take it", action: take).disabled(busy)
                }
                Button("Skip", action: skip).disabled(busy)
                Text(commit.short ?? String(commit.sha.prefix(7))).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

private struct VerdictTag: View {
    var verdict: String
    var why: String?

    var body: some View {
        switch (verdict, why) {
        case ("take", "touches_your_changes"?):
            Label("Touches your changes", systemImage: "hand.raised").font(.caption.weight(.medium)).foregroundStyle(.orange)
        case ("take", "clashes"?):
            Label("Clashes with your copy", systemImage: "arrow.triangle.merge").font(.caption.weight(.medium)).foregroundStyle(.orange)
        case ("take", "breaks_a_test"?):
            Label("Fails a safety test", systemImage: "xmark.octagon").font(.caption.weight(.medium)).foregroundStyle(.red)
        case ("take", _):
            Label("Looks safe", systemImage: "checkmark.seal").font(.caption.weight(.medium)).foregroundStyle(.green)
        case ("skip", _):
            Label("Not in your copy", systemImage: "minus.circle").font(.caption.weight(.medium)).foregroundStyle(.secondary)
        default:
            Label("Needs your look", systemImage: "exclamationmark.triangle").font(.caption.weight(.medium)).foregroundStyle(.orange)
        }
    }
}

/// The one-click card: what Update all takes, how far it is, and what it left.
private struct UpdateAllCard: View {
    var plan: UpdateAllPlan
    var left: Int
    var progress: (done: Int, total: Int)?
    var result: String?
    var busy: Bool
    var start: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(plan.eligible.count) safe changes are ready").font(.headline)
                if let progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    Text("Taking \(progress.done) of \(progress.total), with the safety tests as it goes").font(.callout).foregroundStyle(.secondary)
                } else if let result {
                    Text(result).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("None of them touches what you built on Mole. \(left) other \(left == 1 ? "change stays" : "changes stay") for your look.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            Button("Update all", action: start)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green.opacity(0.25)))
    }
}
