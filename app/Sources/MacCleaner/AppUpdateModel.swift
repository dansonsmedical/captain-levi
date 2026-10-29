import AppKit
import SwiftUI

@MainActor
final class AppUpdateModel: ObservableObject {
    @Published var state: AppUpdateState = .upToDate
    @Published private(set) var offer: UpdateOffer?
    @Published private(set) var errorMessage: String?
    @Published private(set) var checking = false
    @Published private(set) var canCancel = false
    @Published private(set) var oldCopyInTrash = false
    @Published private(set) var lastCheck: Date?
    let bundled: Bool
    let running: AppVersion?
    private let applicationURL = Bundle.main.bundleURL
    private let saveLastCheck: @MainActor (Date) -> Void
    private var installation: Task<Void, Never>?

    init(bundled: Bool,
         version: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
         readLastCheck: @MainActor () -> Date? = { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date },
         saveLastCheck: @escaping @MainActor (Date) -> Void = { UserDefaults.standard.set($0, forKey: "lastUpdateCheck") }) {
        self.bundled = bundled
        self.saveLastCheck = saveLastCheck
        running = AppVersion(version)
        lastCheck = readLastCheck()
    }
    static func due(bundled: Bool, last: Date?, now: Date) -> Bool {
        bundled && (last.map { now.timeIntervalSince($0) >= 24 * 60 * 60 } ?? true)
    }
    func checkIfDue(now: Date = Date()) async {
        await checkIfDue(now: now) { try await UpdateTransport().receive(UpdateTransport.latest, to: nil) }
    }
    func checkIfDue(now: Date, fetch: @MainActor () async throws -> Data) async {
        guard Self.due(bundled: bundled, last: lastCheck, now: now) else { return }
        await performCheck(now: now, fetch: fetch)
    }
    func check(now: Date = Date()) async {
        await performCheck(now: now) { try await UpdateTransport().receive(UpdateTransport.latest, to: nil) }
    }
    /// Dependency seam lets tests count requests without ever evaluating the production address.
    func performCheck(now: Date, fetch: @MainActor () async throws -> Data) async {
        guard bundled, !checking, installation == nil else { return }
        if case .readyToRestart = state { return }
        checking = true
        defer { checking = false }
        lastCheck = now
        saveLastCheck(now)
        do {
            guard let running else { throw UpdateFailure.invalidApp }
            let release = try JSONDecoder().decode(AppRelease.self, from: await fetch())
            offer = try release.offer(running: running)
            errorMessage = nil
            state = offer == nil ? .upToDate : .available
        } catch {
            errorMessage = error.localizedDescription
            state = .couldNotCheck
        }
    }
    func install() {
        install { offer, running, beginVerification, progress in
            try UpdateInstaller.preflight(self.applicationURL)
            try await Self.prepareAndSwap(offer, running: running, id: Bundle.main.bundleIdentifier ?? "", app: self.applicationURL,
                                          beginVerification: beginVerification, progress: progress)
        }
    }
    /// In-process tests supply a worker; production always uses the verified installer above.
    func install(worker: @escaping @MainActor (UpdateOffer, AppVersion, @escaping @MainActor () -> Void, @escaping @Sendable (Double) -> Void) async throws -> Void) {
        guard bundled, !checking, installation == nil, let offer, let running else { return }
        errorMessage = nil
        oldCopyInTrash = false
        canCancel = true
        state = .downloading(0)
        installation = Task { @MainActor in
            do {
                // The worker owns its temporary folders until cancellation/verification has finished.
                try await worker(offer, running, { [weak self] in self?.canCancel = false }) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.installation != nil else { return }
                        self.state = .downloading(progress)
                    }
                }
                state = .readyToRestart
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { state = .available }
                else {
                    if case UpdateFailure.oldInTrash = error { oldCopyInTrash = true }
                    errorMessage = error.localizedDescription; state = .couldNotCheck
                }
            }
            installation = nil
            canCancel = false
        }
    }
    nonisolated static func prepareAndSwap(_ offer: UpdateOffer, running: AppVersion, id: String, app: URL,
                                                  beginVerification: @escaping @MainActor () -> Void,
                                                  progress: @escaping @Sendable (Double) -> Void,
                                                  transport: UpdateTransport = UpdateTransport()) async throws {
        let workspace = try UpdateWorkspace()
        let zip = workspace.download.appendingPathComponent("update.zip")
        _ = try await transport.receive(offer.asset.browser_download_url, to: zip, progress: progress)
        try Task.checkCancellation()
        await beginVerification()
        let verified = try UpdateInstaller.verify(zip, into: workspace.extracted, offer: offer, bundleID: id, running: running)
        try Task.checkCancellation()
        try UpdateInstaller.swap(verified, runningApp: app)
        withExtendedLifetime(workspace) {}
    }
    func cancel() { if canCancel { installation?.cancel() } }
    func restart() {
        guard case .readyToRestart = state else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: config) { _, error in
            Task { @MainActor in
                if let error { self.errorMessage = error.localizedDescription }
                else { NSApp.terminate(nil) }
            }
        }
    }
}

struct LiveAppUpdateView: View {
    @ObservedObject var model: AppUpdateModel
    var body: some View {
        AppUpdateView(state: model.state, model: model)
    }
}
