import AppKit
import CryptoKit
import Foundation

struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [UInt64]
    init?(_ tag: String) {
        guard tag.range(of: #"\Av?[0-9]+\.[0-9]+\.[0-9]+\z"#, options: .regularExpression) != nil else { return nil }
        let values = (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag).split(separator: ".").compactMap { UInt64($0) }
        guard values.count == 3 else { return nil }
        parts = values
    }
    var description: String { parts.map(String.init).joined(separator: ".") }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct AppRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable { let name: String; let size: Int64; let browser_download_url: URL }
    let tag_name: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    static func fingerprint(_ body: String) -> String? {
        let lines = body.components(separatedBy: .newlines).filter { $0.hasPrefix("SHA-256: ") }
        guard lines.count == 1 else { return nil }
        let value = String(lines[0].dropFirst(9))
        guard value.range(of: #"\A[a-fA-F0-9]{64}\z"#, options: .regularExpression) != nil else { return nil }
        return value.lowercased()
    }
    func offer(running: AppVersion) throws -> UpdateOffer? {
        guard !draft, !prerelease else { return nil }
        guard let version = AppVersion(tag_name) else { throw UpdateFailure.invalidRelease }
        guard version > running else { return nil }
        let zips = assets.filter { $0.name.hasSuffix(".zip") }
        guard zips.count == 1, let asset = zips.first, asset.size > 0,
              asset.size <= UpdateTransport.limit, let hash = Self.fingerprint(body ?? "") else { throw UpdateFailure.invalidRelease }
        return UpdateOffer(version: version, notes: String((body ?? "").prefix(600)), asset: asset, hash: hash)
    }
}
struct UpdateOffer: Sendable {
    let version: AppVersion
    let notes: String
    let asset: AppRelease.Asset
    let hash: String
}
enum UpdateFailure: LocalizedError {
    case oldInTrash(String)
    case invalidRelease, unsafeArchive, invalidApp, tooLarge, invalidAddress, fingerprint, moveFirst, failed(String)
    var errorDescription: String? {
        switch self {
        case .oldInTrash(let message): message
        case .fingerprint: "The download did not match the release's fingerprint. Nothing was changed."
        case .moveFirst: "Move Captain Levi to your Applications folder first, then try again."
        case .invalidRelease: "The release could not be checked. Nothing was changed."
        case .unsafeArchive: "The update archive contains an unsafe path. Nothing was changed."
        case .invalidApp: "The update app could not be verified. Nothing was changed."
        case .tooLarge: "The update exceeds 100 MB. Nothing was changed."
        case .invalidAddress: "The update address could not be verified. Nothing was changed."
        case .failed(let message): message
        }
    }
}

/// Redirect policy is shared by checks and downloads. A test transport can only reach loopback.
final class UpdateTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let repository = "dansonsmedical/captain-levi"
    static let latest = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let limit: Int64 = 100_000_000
    private let loopback: Bool
    init(selftest: Bool = false) {
        self.loopback = selftest && CommandLine.arguments.contains("--updater-selftest")
    }
    func allowed(_ url: URL, initialAsset: Bool = false) -> Bool {
        guard !url.path.split(separator: "/").contains("..") else { return false }
        if loopback { return url.scheme == "http" && url.host == "127.0.0.1" && url.user == nil && url.password == nil }
        guard url.scheme == "https", url.port == nil, url.user == nil, url.password == nil,
              !url.path.split(separator: "/").contains("..") else { return false }
        return !initialAsset || (url.host == "github.com" && url.standardized.path.hasPrefix("/\(Self.repository)/releases/download/"))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map { allowed($0) } == true ? request : nil)
    }
    static let checkTimeout: TimeInterval = 15
    static let downloadRequestTimeout: TimeInterval = 30
    static let downloadResourceTimeout: TimeInterval = 600
    func session(download: Bool = false) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        if loopback { config.connectionProxyDictionary = [:] }
        config.timeoutIntervalForRequest = download ? Self.downloadRequestTimeout : Self.checkTimeout
        config.timeoutIntervalForResource = download ? Self.downloadResourceTimeout : Self.checkTimeout
        config.httpAdditionalHeaders = ["Accept": "application/vnd.github+json", "User-Agent": "Captain-Levi", "Accept-Language": "en"]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    /// Writes our own file rather than importing a browser/download-service file or its xattrs.
    func receive(_ url: URL, to destination: URL?, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Data {
        guard allowed(url, initialAsset: destination != nil) else { throw UpdateFailure.invalidAddress }
        let session = session(download: destination != nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.timeoutInterval = destination == nil ? Self.checkTimeout : Self.downloadRequestTimeout
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw UpdateFailure.invalidRelease }
        let ceiling = destination == nil ? Int64(2_000_000) : Self.limit
        guard response.expectedContentLength <= ceiling else { throw UpdateFailure.tooLarge }
        var handle: FileHandle?
        if let destination {
            guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw UpdateFailure.invalidApp }
            handle = try FileHandle(forWritingTo: destination)
        }
        defer { try? handle?.close() }
        var result = Data(), buffer = Data(), count: Int64 = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            count += 1
            guard count <= ceiling else { throw UpdateFailure.tooLarge }
            buffer.append(byte)
            if buffer.count >= 65_536 {
                if let handle { try handle.write(contentsOf: buffer) } else { result.append(buffer) }
                buffer.removeAll(keepingCapacity: true)
                progress(response.expectedContentLength > 0 ? min(Double(count) / Double(response.expectedContentLength), 1) : 0)
            }
        }
        if let handle { try handle.write(contentsOf: buffer) } else { result.append(buffer) }
        progress(1)
        return result
    }
}

/// Owns exactly two fresh temporary directories. Cleanup never walks arbitrary caller paths.
final class UpdateWorkspace {
    let download: URL
    let extracted: URL
    init() throws {
        let fm = FileManager.default
        download = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("levi-download-" + UUID().uuidString)
        extracted = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("levi-extract-" + UUID().uuidString)
        try fm.createDirectory(at: download, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do { try fm.createDirectory(at: extracted, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { try? fm.removeItem(at: download); throw error }
    }
    deinit { try? FileManager.default.removeItem(at: download); try? FileManager.default.removeItem(at: extracted) }
}

enum UpdateInstaller {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.invalidApp }
        return data
    }
    static func digest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 65_536), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func verify(_ zip: URL, into folder: URL, offer: UpdateOffer, bundleID: String, running: AppVersion) throws -> URL {
        guard try digest(zip) == offer.hash else { throw UpdateFailure.fingerprint }
        // Validate before ditto can follow a link or an escaping member during extraction.
        let paths = String(decoding: try run("/usr/bin/zipinfo", ["-1", zip.path]), as: UTF8.self).split(separator: "\n")
        guard !paths.isEmpty, paths.allSatisfy({ !$0.hasPrefix("/") && !$0.contains("\\") && !$0.split(separator: "/").contains("..") }) else { throw UpdateFailure.unsafeArchive }
        let listing = String(decoding: try run("/usr/bin/zipinfo", ["-l", zip.path]), as: UTF8.self)
        guard !listing.split(separator: "\n").contains(where: { $0.first == "l" }) else { throw UpdateFailure.unsafeArchive }
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.path])
        let app = folder.appendingPathComponent("Captain Levi.app", isDirectory: true)
        let fm = FileManager.default
        var enumerationFailed = false
        guard (try? app.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              let items = fm.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else { throw UpdateFailure.invalidApp }
        for item in [app] + items.allObjects.compactMap({ $0 as? URL }) {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, item.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/") else { throw UpdateFailure.unsafeArchive }
        }
        guard !enumerationFailed else { throw UpdateFailure.unsafeArchive }
        let plist = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              let text = info["CFBundleShortVersionString"] as? String, let version = AppVersion(text),
              version == offer.version, version > running else { throw UpdateFailure.invalidApp }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }
    static func permittedParent(_ parent: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                resolve: (URL) -> URL = { $0.standardizedFileURL.resolvingSymlinksInPath() }) -> Bool {
        let path = resolve(parent).path
        return [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].contains { resolve($0).path == path }
    }
    static func preflight(_ app: URL, permitted: (URL) -> Bool = { permittedParent($0) }) throws {
        guard !app.path.contains("/AppTranslocation/"), !app.resolvingSymlinksInPath().path.contains("/AppTranslocation/") else { throw UpdateFailure.moveFirst }
        let parent = app.deletingLastPathComponent()
        guard permitted(parent) else { throw UpdateFailure.moveFirst }
        let attributes = try? FileManager.default.attributesOfItem(atPath: parent.path)
        let mode = attributes?[.posixPermissions] as? NSNumber
        guard (mode?.intValue ?? 0) & 0o222 != 0, FileManager.default.isWritableFile(atPath: parent.path) else { throw UpdateFailure.moveFirst }
    }
    /// The trash operation is injected only by the in-process tests, never by app preferences.
    static func swap(_ newApp: URL, runningApp: URL, trash: (URL) throws -> URL? = { app in
        var result: NSURL?
        try FileManager.default.trashItem(at: app, resultingItemURL: &result)
        return result.map { $0 as URL }
    }, preflight: (URL) throws -> Void = { try UpdateInstaller.preflight($0) }, afterTrash: () throws -> Void = {}) throws {
        try preflight(runningApp)
        let fm = FileManager.default
        let staged = runningApp.deletingLastPathComponent().appendingPathComponent(".levi-update-" + UUID().uuidString + ".app")
        // Failed staging copies go to the Trash, never permanent deletion.
        defer { if fm.fileExists(atPath: staged.path) { _ = try? trash(staged) } }
        try fm.copyItem(at: newApp, to: staged)
        let old = try trash(runningApp)
        do {
            try afterTrash()
            try fm.moveItem(at: staged, to: runningApp)
        } catch {
            let swapError = error
            guard let old else { throw UpdateFailure.oldInTrash("The update could not be installed. Your old copy is safe in the Trash.") }
            let launchWasAbsent = !fm.fileExists(atPath: runningApp.path)
            do { try fm.moveItem(at: old, to: runningApp) }
            catch {
                // A cross-volume move may have begun copying before it failed.
                if launchWasAbsent, fm.fileExists(atPath: runningApp.path) { _ = try? trash(runningApp) }
                // Keep the intact old app in the Trash and trash the staged update via defer.
                // Do not attempt a copy restore: it can leave a partial launch app and a
                // redundant old copy in the Trash. Both retained versions remain recoverable.
                throw UpdateFailure.oldInTrash("The old copy is safe in the Trash. It could not be restored: \(error.localizedDescription)")
            }
            throw UpdateFailure.failed(swapError.localizedDescription)
        }
    }
}
