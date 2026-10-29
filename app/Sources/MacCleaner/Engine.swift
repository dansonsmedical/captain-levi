import Foundation

enum EngineError: LocalizedError {
    case notFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: Bundle.main.bundleURL.pathExtension == "app"
            ? "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Captain Levi")'s files are missing; reinstall the app"
            : "Captain Levi could not find its engine."
        case .failed(let message): message
        }
    }
}

/// Runs this copy of the cleaner: the dry-run scan (bin/clean.sh, which only ever looks) and
/// engine/apply.sh, which deletes only the ticked plan items inside the user's home folder.
final class Engine: @unchecked Sendable {
    let root: URL
    let home: String
    let dataDir: URL

    init(root: URL, home: String = NSHomeDirectory(), dataDir: URL? = nil) throws {
        self.root = root
        self.home = home
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.dataDir = dataDir ?? support.appendingPathComponent("Mac Cleaner", isDirectory: true)
        try FileManager.default.createDirectory(at: self.dataDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    /// Bundled files are authoritative, including when broken.
    static func locateRoot() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("engine", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            guard FileManager.default.fileExists(atPath: bundled.path + "/bin/clean.sh"),
                  FileManager.default.fileExists(atPath: bundled.path + "/engine/apply.sh") else { return nil }
            return bundled
        }
        var candidates: [String] = []
        if let env = ProcessInfo.processInfo.environment["MAC_CLEANER_ENGINE"] { candidates.append(env) }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("engine", isDirectory: true).path)
        }
        if let url = Bundle.main.url(forResource: "EngineRoot", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            candidates.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let fm = FileManager.default
        return candidates.first { fm.fileExists(atPath: $0 + "/bin/clean.sh") && fm.fileExists(atPath: $0 + "/engine/apply.sh") }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Whether the resolved engine root is inside this app's resources.
    var isBundled: Bool {
        guard let resources = Bundle.main.resourceURL?.resolvingSymlinksInPath().path else { return false }
        return root.resolvingSymlinksInPath().path.hasPrefix(resources + "/")
    }

    var planURL: URL { dataDir.appendingPathComponent("plan.bin") }
    var installerPlanURL: URL { dataDir.appendingPathComponent("installers.bin") }
    var uninstallPlanURL: URL { dataDir.appendingPathComponent("uninstall-plan.bin") }
    var historyURL: URL { dataDir.appendingPathComponent("history.tsv") }

    /// A small, fixed environment: nothing from the app's own environment can bend the engine.
    private var environment: [String: String] {
        [
            "HOME": home, "USER": NSUserName(), "LOGNAME": NSUserName(),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin",
            "TMPDIR": NSTemporaryDirectory(), "NO_COLOR": "1", "TERM": "dumb", "LANG": "en_US.UTF-8",
        ]
    }

    /// Runs one of the engine's scripts with /bin/bash; streams each output line and returns the exit status.
    func run(_ script: String, _ arguments: [String], onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [root.appendingPathComponent(script).path] + arguments
        process.environment = environment
        process.currentDirectoryURL = dataDir
        if isBundled && script.hasPrefix("updates/") {
            throw EngineError.failed("Mole updates are available only in a source checkout.")
        }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
        for try await line in output.fileHandleForReading.bytes.lines {
            onLine(line)
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// The dry run. Deletes nothing; returns the plan's records.
    func scan(onSection: @escaping @Sendable (String) -> Void) async throws -> [PlanRecord] {
        try? FileManager.default.removeItem(at: planURL)
        let status = try await run("bin/clean.sh", ["--plan-out", planURL.path]) { line in
            if line.hasPrefix("➤ ") { onSection(String(line.dropFirst(2))) }
        }
        guard status == 0 else { throw EngineError.failed("The scan stopped early (code \(status)). Nothing was deleted.") }
        guard FileManager.default.fileExists(atPath: planURL.path) else { return [] }
        return try PlanRecord.read(from: planURL)
    }

    var projectsPlanURL: URL { dataDir.appendingPathComponent("projects.bin") }
    var projectsMetaURL: URL { dataDir.appendingPathComponent("projects.bin.meta") }
    /// Extra folders the user has named for the Project folders scan, one absolute path per line (none by default).
    var projectRootsURL: URL { dataDir.appendingPathComponent("project-roots.txt") }

    private var extraProjectRoots: [String] {
        guard let text = try? String(contentsOf: projectRootsURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter { $0.hasPrefix("/") }
    }

    /// The Project folders dry run (bin/projects.sh). Deletes nothing; returns the plan's records and their display meta.
    func scanProjects(onSection: @escaping @Sendable (String) -> Void) async throws -> (records: [PlanRecord], meta: [String: ProjectMeta]) {
        try? FileManager.default.removeItem(at: projectsPlanURL)
        try? FileManager.default.removeItem(at: projectsMetaURL)
        let arguments = ["--plan-out", projectsPlanURL.path] + extraProjectRoots.flatMap { ["--root", $0] }
        let status = try await run("bin/projects.sh", arguments) { line in
            if line.hasPrefix("➤ ") { onSection(String(line.dropFirst(2))) }
        }
        guard status == 0 else { throw EngineError.failed("The look for project folders stopped early (code \(status)). Nothing was deleted.") }
        guard FileManager.default.fileExists(atPath: projectsPlanURL.path) else { return ([], [:]) }
        return (try PlanRecord.read(from: projectsPlanURL), ProjectMeta.read(from: projectsMetaURL))
    }

    /// Deletes (or, with trash, moves to the Trash) exactly these ticked paths from a plan. With `projects`, they are
    /// Project folders items: apply.sh checks each again, and `allowRecent` lists the "in use lately" ones the user ticked
    /// on purpose.
    func apply(_ paths: [String], planFile: URL, trash: Bool, projects: Bool = false, uninstall: Bool = false,
               allowRecent: [String] = []) async throws -> [ApplyResult] {
        let approved = dataDir.appendingPathComponent(uninstall ? "approved-uninstall.bin" : projects ? "approved-projects.bin" : (trash ? "approved-installers.bin" : "approved.bin"))
        var data = Data()
        for path in paths {
            data.append(contentsOf: Array(path.utf8))
            data.append(0)
        }
        try data.write(to: approved, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: approved.path)

        let collected = LineCollector()
        var arguments = ["--plan", planFile.path, "--approved", approved.path, "--log", historyURL.path]
        // Uninstall has its own allowed folders (Library places and the app's own bundle in Applications), so no jail at home.
        if uninstall { arguments.append("--uninstall") } else { arguments += ["--jail", home] }
        if trash { arguments.append("--trash") }
        if projects {
            let allowed = dataDir.appendingPathComponent("allow-recent.bin")
            var allowData = Data()
            for path in allowRecent where paths.contains(path) {
                allowData.append(contentsOf: Array(path.utf8))
                allowData.append(0)
            }
            try allowData.write(to: allowed, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: allowed.path)
            arguments += ["--projects", "--allow-recent", allowed.path] + extraProjectRoots.flatMap { ["--root", $0] }
        }
        let status = try await run("engine/apply.sh", arguments) { collected.add($0) }
        guard status == 0 else {
            throw EngineError.failed("Cleaning stopped (code \(status)). \(collected.lines.last ?? "")")
        }
        return collected.lines.compactMap { line in
            let f = line.components(separatedBy: "\t")
            guard f.count >= 3 else { return nil }
            return ApplyResult(status: f[0], bytes: (Int64(f[1]) ?? 0) * 1024, path: f[2], reason: f.count > 3 ? f[3] : "")
        }
    }

    /// Installer files directly in Downloads or Desktop, or one folder down. Reading these folders is what makes
    /// macOS ask once for permission, so this runs only when the user asks for it.
    func findInstallers() -> [PlanRecord] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var records: [PlanRecord] = []
        for folder in ["Downloads", "Desktop"] {
            let base = URL(fileURLWithPath: home).appendingPathComponent(folder, isDirectory: true)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                if walker.level > 2 {
                    walker.skipDescendants()
                    continue
                }
                guard ["dmg", "pkg", "mpkg", "iso", "xip"].contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                records.append(PlanRecord(section: "Old installers", path: url.path, kb: Int64(values.fileSize ?? 0) / 1024,
                                          count: 1, sizeKnown: true, coveredBy: ""))
            }
        }
        return records.sorted { $0.kb > $1.kb }
    }

    func history() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: historyURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").reversed().compactMap { line in
            let f = line.components(separatedBy: "\t")
            guard f.count >= 4 else { return nil }
            return HistoryEntry(time: f[0], status: f[1], bytes: (Int64(f[2]) ?? 0) * 1024, path: f[3],
                                reason: f.count > 4 ? f[4] : "")
        }
    }

    static func disk(home: String) -> (free: Int64, total: Int64) {
        let values = try? URL(fileURLWithPath: home).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0), Int64(values?.volumeTotalCapacity ?? 0))
    }
}

/// Collects output lines from the engine across threads.
final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func add(_ line: String) { lock.lock(); storage.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
