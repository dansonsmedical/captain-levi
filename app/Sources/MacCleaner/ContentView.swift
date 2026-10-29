import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case clean, projects, uninstall, installers, updates, appUpdates, history
    static func available(isBundled: Bool) -> [Pane] {
        allCases.filter { pane in
            switch pane {
            case .updates: !isBundled
            case .appUpdates: isBundled
            default: true
            }
        }
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clean: "Clean"
        case .projects: "Project folders"
        case .uninstall: "Uninstall apps"
        case .installers: "Old installers"
        case .updates: "Updates from Mole"
        case .appUpdates: "Captain Levi updates"
        case .history: "History"
        }
    }
    var symbol: String {
        switch self {
        case .clean: "sparkles"
        case .projects: "folder"
        case .uninstall: "xmark.bin"
        case .installers: "shippingbox.and.arrow.backward"
        case .updates: "arrow.down.circle"
        case .appUpdates: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdatesModel
    @StateObject private var appUpdates: AppUpdateModel
    @State var pane: Pane
    /// A picture-only fixture also gives the sidebar the brothers' bundled appearance.
    var appUpdateFixture: AppUpdateState?
    private var isBundled: Bool { appUpdateFixture != nil || updates.engine?.isBundled == true }

    init(model: AppModel, updates: UpdatesModel, pane: Pane = .clean, appUpdateFixture: AppUpdateState? = nil,
         appUpdates: AppUpdateModel? = nil) {
        _model = ObservedObject(wrappedValue: model)
        _updates = ObservedObject(wrappedValue: updates)
        _appUpdates = StateObject(wrappedValue: appUpdates ?? AppUpdateModel(bundled: appUpdateFixture == nil && updates.engine?.isBundled == true))
        self.appUpdateFixture = appUpdateFixture
        let bundled = appUpdateFixture != nil || updates.engine?.isBundled == true
        _pane = State(initialValue: Pane.available(isBundled: bundled).contains(pane) ? pane : .clean)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(Pane.available(isBundled: isBundled)) { p in
                    Label(p.title, systemImage: p.symbol)
                        .badge(p == .updates ? updates.pendingCount : 0)
                        .tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 236)
            .safeAreaInset(edge: .bottom) {
                if !isBundled {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your copy of Mole").font(.caption.weight(.medium))
                    Text(updates.footer).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                }
            }
        } detail: {
            Group {
                switch pane {
                case .clean: CleanView(model: model)
                case .projects: ProjectsView(model: model)
                case .uninstall: UninstallView(model: model.uninstall)
                case .installers: InstallersView(model: model)
                case .updates: UpdatesView(model: updates)
                case .appUpdates:
                    if let appUpdateFixture { AppUpdateView(state: appUpdateFixture) }
                    else { LiveAppUpdateView(model: appUpdates) }
                case .history: HistoryView(model: model)
                }
            }
            // The window's smallest size is set here, on the detail pane: a frame around the whole
            // NavigationSplitView leaves the window blank on macOS 26.
            .frame(minWidth: 620, minHeight: 560)
        }
        .onChange(of: model.requestedPane) { _, requested in
            if let requested {
                if Pane.available(isBundled: isBundled).contains(requested) { pane = requested }
                model.requestedPane = nil
            }
        }
        .task { await appUpdates.checkIfDue() }
    }
}
