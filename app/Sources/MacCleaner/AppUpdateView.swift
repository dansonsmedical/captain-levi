import SwiftUI

/// Shared by the live updater and the approved picture fixtures.
enum AppUpdateState {
    case upToDate
    case available
    case downloading(Double)
    case readyToRestart
    case couldNotCheck

    static let fixtures: [(name: String, state: AppUpdateState)] = [
        ("uptodate", .upToDate), ("available", .available),
        ("downloading", .downloading(0.62)), ("restart", .readyToRestart),
        ("error", .couldNotCheck)
    ]

    var title: String {
        switch self {
        case .upToDate: "Captain Levi is up to date"
        case .couldNotCheck: "Could not check for updates"
        case .downloading: "Downloading the update"
        case .readyToRestart: "Update installed"
        default: "A new version is ready"
        }
    }

    var subtitle: String {
        switch self {
        case .upToDate:
            "Version 1.0.0. Last checked Oct 29, 2026 at 9:41 AM. Nothing installs without your click."
        case .couldNotCheck:
            "Captain Levi could not reach GitHub."
        default:
            "You have 1.0.0. Last checked Oct 29, 2026 at 9:41 AM."
        }
    }
}

struct AppUpdateView: View {
    var state: AppUpdateState
    var model: AppUpdateModel? = nil
    private var version: String { model?.offer?.version.description ?? "1.1.0" }
    private var size: String {
        guard let asset = model?.offer?.asset else { return "3.6 MB" }
        return String(format: "%.1f MB", Double(asset.size) / 1_000_000)
    }
    private var subtitle: String {
        guard let model else { return state.subtitle }
        if case .readyToRestart = state, let message = model.errorMessage { return message }
        if case .couldNotCheck = state { return model.errorMessage ?? "Captain Levi could not reach GitHub." }
        let checked = model.lastCheck.map { " Last checked \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
        let current = model.running?.description ?? "unknown"
        if case .upToDate = state { return "Version \(current).\(checked) Nothing installs without your click." }
        return "You have \(current).\(checked)"
    }

    var body: some View {
        List {
            Section {
                if case .available = state {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's new").font(.headline)
                        if let model { Text(model.offer?.notes ?? "") }
                        else {
                            Text("The Uninstall pane now shows what is left behind.")
                            Text("A rare crash when the menu bar card opened is fixed.")
                            Text("Scanning large Downloads folders is faster.")
                        }
                    }
                    .font(.callout)
                    .padding(.vertical, 6)
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.title).font(.system(size: 30, weight: .bold))
                    Text(subtitle).foregroundStyle(.secondary)
                    switch state {
                    case .upToDate:
                        Button("Check now") { Task { await model?.check() } }.disabled(model?.checking == true).padding(.top, 4)
                    case .couldNotCheck:
                        Button("Try again") { Task { await model?.check() } }.disabled(model?.checking == true).padding(.top, 4)
                        Text(model?.oldCopyInTrash == true ? "Your old copy is safe in the Trash." : "Nothing was installed or removed.")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.10)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.25)))
                            .padding(.top, 10)
                    default:
                        updateCard.padding(.top, 10)
                    }
                }
                .textCase(nil)
                .padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
        .toolbar(removing: .title)
    }

    // Keep the spacing, type, native button styles and colours of UpdateAllCard.
    private var updateCard: some View {
        HStack(alignment: .center, spacing: 14) {
            if case .downloading = state {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 26)).foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 3) {
                switch state {
                case .downloading(let progress):
                    Text("Downloading version \(version)").font(.headline)
                    ProgressView(value: progress, total: 1)
                    Text("\(Int((progress * 100).rounded())) percent of \(size)")
                        .font(.callout).foregroundStyle(.secondary)
                case .readyToRestart:
                    Text("Version \(version) is installed").font(.headline)
                    Text("Captain Levi restarts to finish. Your old copy is in the Trash if you need it.")
                        .font(.callout).foregroundStyle(.secondary)
                default:
                    Text("Version \(version) is ready").font(.headline)
                    Text(model == nil ? "Fixes three problems. About 3.6 MB. Checked against the release's fingerprint before it installs." : "About \(size). Checked against the release's fingerprint before it installs.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            switch state {
            case .downloading:
                Button("Cancel") { model?.cancel() }.controlSize(.large).disabled(model?.canCancel == false)
            case .readyToRestart:
                Button("Restart now") { model?.restart() }.buttonStyle(.borderedProminent).controlSize(.large)
            default:
                Button("Install update") { model?.install() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.green.opacity(0.25)))
    }
}
