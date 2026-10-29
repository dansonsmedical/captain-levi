import Foundation

/// Hidden, in-process tests. All HTTP uses an explicitly supplied IPv4 loopback server.
@MainActor
enum UpdaterSelfTest {
    static func run(_ arguments: [String]) async -> Int32 {
        var failures = 0
        var note = "No additional detail supplied"
        @MainActor func check(_ name: String, _ body: @MainActor () throws -> Bool) {
            note = "No additional detail supplied"
            do {
                if try body() { print("PASS \(name)") }
                else { failures += 1; print("FAIL \(name)"); print("  \(note)") }
            } catch { failures += 1; print("FAIL \(name)"); print("  \(note); thrown=\(type(of: error)): \(error)") }
        }
        @MainActor func refuses(_ body: @MainActor () throws -> Void) -> Bool {
            do { try body(); return false } catch { return true }
        }
        guard arguments.count == 2, let base = URL(string: arguments[0]),
              base.scheme == "http", base.host == "127.0.0.1", base.user == nil, base.password == nil else {
            print("FAIL loopback fixture arguments"); return 1
        }
        let fixtures = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let running = AppVersion("1.0.0")!, newer = AppVersion("1.1.0")!
        let hash = String(repeating: "a", count: 64)
        check("timeout constants") { UpdateTransport.checkTimeout == 15 && UpdateTransport.downloadRequestTimeout == 30 && UpdateTransport.downloadResourceTimeout == 600 }
        let fakeHome = URL(fileURLWithPath: "/fixture/home")
        check("Applications parents only without folder access") {
            UpdateInstaller.permittedParent(URL(fileURLWithPath: "/Applications"), home: fakeHome, resolve: { $0.standardizedFileURL })
                && UpdateInstaller.permittedParent(fakeHome.appendingPathComponent("Applications"), home: fakeHome, resolve: { $0.standardizedFileURL })
                && !UpdateInstaller.permittedParent(fakeHome.appendingPathComponent("Desktop"), home: fakeHome, resolve: { $0.standardizedFileURL })
        }
        nonisolated func release(_ names: [String], body: String? = nil, tag: String = "v1.1.0", draft: Bool = false, prerelease: Bool = false) -> AppRelease {
            AppRelease(tag_name: tag, body: body ?? "Notes\nSHA-256: \(hash)", draft: draft, prerelease: prerelease,
                       assets: names.map { AppRelease.Asset(name: $0, size: 100, browser_download_url: base.appendingPathComponent($0)) })
        }
        check("version numeric 1.10.0 > 1.9.0") { AppVersion("1.10.0")! > AppVersion("1.9.0")! }
        check("version equal") { AppVersion("v1.0.0") == running }
        check("version older") { running < newer }
        check("bad tags") { ["1.0", "1.2.3-beta", "v1.2.3\n", " 1.2.3", "1.2.3.4", "V1.2.3"].allSatisfy { AppVersion($0) == nil } }
        check("one zip") { try release(["app.zip", "notes.txt"]).offer(running: running) != nil }
        check("no zip") { refuses { _ = try release([]).offer(running: running) } }
        check("two zips") { refuses { _ = try release(["a.zip", "b.zip"]).offer(running: running) } }
        check("dotted zip name") { try release(["Captain.Levi-1.1.0.zip"]).offer(running: running) != nil }
        check("draft ignored") { try release(["a.zip"], draft: true).offer(running: running) == nil }
        check("prerelease ignored") { try release(["a.zip"], prerelease: true).offer(running: running) == nil }
        check("SHA line present") { AppRelease.fingerprint("Notes\nSHA-256: \(hash)\n") == hash }
        check("SHA line missing") { AppRelease.fingerprint("Notes") == nil }
        check("SHA wrong length") { AppRelease.fingerprint("SHA-256: " + String(hash.dropLast())) == nil }
        check("missing SHA refuses offer") { refuses { _ = try release(["a.zip"], body: "Notes").offer(running: running) } }
        check("oversize asset refused") {
            let asset = AppRelease.Asset(name: "a.zip", size: UpdateTransport.limit + 1, browser_download_url: base)
            return refuses { _ = try AppRelease(tag_name: "v1.1.0", body: "SHA-256: \(hash)", draft: false, prerelease: false, assets: [asset]).offer(running: running) }
        }
        check("production asset URL restrictions") {
            let transport = UpdateTransport()
            return transport.allowed(URL(string: "https://github.com/\(UpdateTransport.repository)/releases/download/v1.1.0/a.zip")!, initialAsset: true)
                && !transport.allowed(base, initialAsset: true)
                && !transport.allowed(URL(string: "https://api.github.com/a.zip")!, initialAsset: true)
                && !transport.allowed(URL(string: "http://github.com/a.zip")!)
        }
        check("test transport refuses outside loopback") {
            !UpdateTransport(selftest: true).allowed(UpdateTransport.latest)
                && !UpdateTransport(selftest: true).allowed(URL(string: "http://localhost/a.zip")!)
        }
        let releaseURL = "https://github.com/\(UpdateTransport.repository)/releases/download/v1.1.0/a.zip"
        for (name, address, expected) in [
            ("exact release download", releaseURL, true),
            ("explicit 443", releaseURL.replacingOccurrences(of: "github.com/", with: "github.com:443/"), false),
            ("dot dot", releaseURL.replacingOccurrences(of: "/a.zip", with: "/../a.zip"), false),
            ("encoded dot dot", releaseURL.replacingOccurrences(of: "/a.zip", with: "/%2e%2e/a.zip"), false),
            ("URL user", releaseURL.replacingOccurrences(of: "https://", with: "https://user@"), false)
        ] {
            check("asset URL \(name)") { UpdateTransport().allowed(URL(string: address)!, initialAsset: true) == expected }
        }
        do {
            let workspace = try UpdateWorkspace()
            let applications = workspace.download.appendingPathComponent("Applications")
            try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: false)
            let installed = applications.appendingPathComponent("Captain Levi.app")
            try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: false)
            let marker = installed.appendingPathComponent("old")
            try Data("old".utf8).write(to: marker)
            let goodZip = fixtures.appendingPathComponent("good.zip")
            nonisolated func offer(_ file: String, hash override: String? = nil, version: AppVersion? = nil) throws -> UpdateOffer {
                let local = fixtures.appendingPathComponent(file)
                let expected = try override ?? UpdateInstaller.digest(local)
                return UpdateOffer(version: version ?? newer, notes: "", asset: .init(name: file, size: 100, browser_download_url: base.appendingPathComponent(file)), hash: expected)
            }
            let zip = workspace.download.appendingPathComponent("received.zip")
            let good = try offer("good.zip")
            _ = try await UpdateTransport(selftest: true).receive(base.appendingPathComponent("redirect.zip"), to: zip)
            check("allowed loopback redirect downloads zip") { try UpdateInstaller.digest(zip) == UpdateInstaller.digest(goodZip) }
            for name in ["outside.zip", "file.zip"] {
                var invalidRelease = false
                var refusedScheme = false
                var receivedBytes = 0
                var fileResponse = false
                var detail = "No response"
                // Use the production delegate: selftest mode permits every loopback port.
                // Bypass only the initial-address gate to make the fixture request locally.
                // Both CFNetwork and the delegate refuse HTTP-to-file redirects.
                // Accept unsupportedURL or noPermissionsToReadFile (-1102): CFNetwork
                // can reject file:// before the delegate sees it, citing the original HTTP URL.
                let session = UpdateTransport().session(download: true)
                do {
                    let (bytes, response) = try await session.bytes(for: URLRequest(url: base.appendingPathComponent(name)))
                    fileResponse = response.url?.isFileURL == true
                    detail = "HTTP status=\(String(describing: (response as? HTTPURLResponse)?.statusCode))"
                    guard let http = response as? HTTPURLResponse else { throw UpdateFailure.invalidApp }
                    if http.statusCode == 302 { throw UpdateFailure.invalidRelease }
                    guard http.statusCode == 200 else { throw UpdateFailure.invalidApp }
                    for try await _ in bytes { receivedBytes += 1 }
                } catch {
                    detail = "error=\(type(of: error)): \(error); \(error.localizedDescription)"
                    if case UpdateFailure.invalidRelease = error { invalidRelease = true }
                    if let urlError = error as? URLError {
                        refusedScheme = urlError.code == .unsupportedURL || urlError.code == .noPermissionsToReadFile
                        detail += "; URLError.code=\(urlError.code.rawValue)"
                    }
                }
                session.invalidateAndCancel()
                check(name == "file.zip" ? "redirect policy refuses file.zip" : "redirect policy exact invalidRelease \(name)") {
                    note = "\(detail); receivedBytes=\(receivedBytes); fileResponse=\(fileResponse)"
                    return (invalidRelease || (name == "file.zip" && refusedScheme)) && receivedBytes == 0 && !fileResponse
                }
            }
            _ = try await UpdateTransport(selftest: true).receive(base.appendingPathComponent("check.json"), to: nil)
            _ = try await UpdateTransport(selftest: true).receive(good.asset.browser_download_url, to: zip)
            check("check and zip headers use English without cookies") {
                let data = try Data(contentsOf: fixtures.appendingPathComponent("headers.json"))
                let requests = try JSONSerialization.jsonObject(with: data) as! [[String: String]]
                return ["/check.json", "/good.zip"].allSatisfy { path in
                    let matching = requests.filter { $0["path"] == path }
                    return !matching.isEmpty && matching.allSatisfy { $0["accept-language"] == "en" && $0["cookie"] == nil }
                }
            }
            let app = try UpdateInstaller.verify(zip, into: workspace.extracted, offer: good, bundleID: "app.captainlevi.cleaner", running: running)
            check("real download verify extract") { try UpdateInstaller.digest(zip) == UpdateInstaller.digest(goodZip) }
            check("other top-level files ignored") { FileManager.default.fileExists(atPath: workspace.extracted.appendingPathComponent("Start here.png").path) }
            check("download and app have no quarantine") {
                let items = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }
                return ([zip, app] + items).allSatisfy { file in
                    refuses { try UpdateInstaller.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", file.path]) }
                }
            }
            check("Info.plist has no quarantine override") {
                let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
                let info = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
                return info["LSFileQuarantineEnabled"] == nil
            }
            check("checksum mismatch leaves install untouched") {
                let bad = try offer("good.zip", hash: String(repeating: "0", count: 64))
                do { _ = try UpdateInstaller.verify(zip, into: workspace.extracted, offer: bad, bundleID: "app.captainlevi.cleaner", running: running); return false }
                catch { return error.localizedDescription == "The download did not match the release's fingerprint. Nothing was changed." && FileManager.default.fileExists(atPath: marker.path) }
            }
            check("checksum refusal deletes owned temp folders") {
                var paths: [URL] = []
                @MainActor func attempt() throws {
                    let rejected = try UpdateWorkspace()
                    paths = [rejected.download, rejected.extracted]
                    let target = rejected.download.appendingPathComponent("update.zip")
                    try FileManager.default.copyItem(at: zip, to: target)
                    _ = try UpdateInstaller.verify(target, into: rejected.extracted, offer: offer("good.zip", hash: String(repeating: "0", count: 64)), bundleID: "app.captainlevi.cleaner", running: running)
                    withExtendedLifetime(rejected) {}
                }
                return refuses { try attempt() } && paths.count == 2 && paths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
            }
            var cancelledPaths: [URL] = []
            let cancelModel = AppUpdateModel(bundled: true, version: "1.0.0", readLastCheck: { nil }, saveLastCheck: { _ in })
            let cancelPayload = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.1.0", "body": "SHA-256: \(hash)", "draft": false, "prerelease": false, "assets": [["name": "slow.zip", "size": 1000000, "browser_download_url": base.appendingPathComponent("slow.zip").absoluteString]]])
            await cancelModel.performCheck(now: Date()) { cancelPayload }
            cancelModel.install { candidate, _, _, _ in
                    let owned = try UpdateWorkspace()
                    defer { withExtendedLifetime(owned) {} }
                    cancelledPaths = [owned.download, owned.extracted]
                    _ = try await UpdateTransport(selftest: true).receive(candidate.asset.browser_download_url, to: owned.download.appendingPathComponent("cancelled.zip"))
            }
            try await Task.sleep(nanoseconds: 200_000_000)
            cancelModel.cancel()
            for _ in 0..<200 where cancelModel.canCancel { try await Task.sleep(nanoseconds: 10_000_000) }
            check("cancelled download cleans owned folders") {
                guard case .available = cancelModel.state else { return false }
                return cancelledPaths.count == 2 && cancelledPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
                    && FileManager.default.fileExists(atPath: marker.path)
            }
            let realCancelModel = AppUpdateModel(bundled: true, version: "1.0.0", readLastCheck: { nil }, saveLastCheck: { _ in })
            await realCancelModel.performCheck(now: Date()) { cancelPayload }
            let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            func ownedFolders() throws -> Set<URL> {
                Set(try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil).filter {
                    $0.lastPathComponent.hasPrefix("levi-download-") || $0.lastPathComponent.hasPrefix("levi-extract-")
                })
            }
            let beforeCancel = try ownedFolders()
            let installBeforeCancel = Set(try FileManager.default.contentsOfDirectory(atPath: applications.path))
            realCancelModel.install { candidate, version, beginVerification, progress in
                try await AppUpdateModel.prepareAndSwap(candidate, running: version, id: "app.captainlevi.cleaner", app: installed,
                    beginVerification: beginVerification, progress: progress, transport: UpdateTransport(selftest: true))
            }
            var realCancelPaths = Set<URL>()
            var downloadStarted = false
            for _ in 0..<200 {
                realCancelPaths = try ownedFolders().subtracting(beforeCancel)
                // Both folders precede the network await; update.zip need not exist yet.
                downloadStarted = realCancelPaths.count == 2
                    && realCancelPaths.contains { $0.lastPathComponent.hasPrefix("levi-download-") }
                    && realCancelPaths.contains { $0.lastPathComponent.hasPrefix("levi-extract-") }
                if downloadStarted { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            realCancelModel.cancel()
            for _ in 0..<200 where realCancelModel.canCancel { try await Task.sleep(nanoseconds: 10_000_000) }
            check("real prepareAndSwap cancellation removes both folders and preserves install") {
                let installAfter = Set(try FileManager.default.contentsOfDirectory(atPath: applications.path))
                let markerAfter = try Data(contentsOf: marker)
                let existence = realCancelPaths.map { "\($0.path)=\(FileManager.default.fileExists(atPath: $0.path))" }.sorted()
                note = "downloadStarted=\(downloadStarted); realCancelPaths.count=\(realCancelPaths.count); exists=\(existence); state=\(realCancelModel.state); installAfter == installBeforeCancel=\(installAfter == installBeforeCancel); markerUnchanged=\(markerAfter == Data("old".utf8))"
                guard case .available = realCancelModel.state else { return false }
                return downloadStarted && realCancelPaths.count == 2 && realCancelPaths.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
                    && installAfter == installBeforeCancel && markerAfter == Data("old".utf8)
            }
            check("extracted symlink fixture passes strict codesign") {
                let space = try UpdateWorkspace()
                try UpdateInstaller.run("/usr/bin/ditto", ["-x", "-k", fixtures.appendingPathComponent("symlink.zip").path, space.extracted.path])
                try UpdateInstaller.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", space.extracted.appendingPathComponent("Captain Levi.app").path])
                return true
            }
            check("signed symlink specifically unsafeArchive") {
                // Removing both symlink guards makes this signed, internal-link fixture pass.
                let space = try UpdateWorkspace()
                do { _ = try UpdateInstaller.verify(fixtures.appendingPathComponent("symlink.zip"), into: space.extracted, offer: offer("symlink.zip"), bundleID: "app.captainlevi.cleaner", running: running); return false }
                catch UpdateFailure.unsafeArchive { return true }
                catch { return false }
            }
            for name in ["wrong-id", "same", "older", "unsigned"] {
                check("\(name) refused") {
                    let local = fixtures.appendingPathComponent(name + ".zip")
                    let testSpace = try UpdateWorkspace()
                    return refuses { _ = try UpdateInstaller.verify(local, into: testSpace.extracted, offer: offer(name + ".zip"), bundleID: "app.captainlevi.cleaner", running: running) }
                }
            }
            check("same version refused even when tag agrees") {
                let testSpace = try UpdateWorkspace()
                return refuses { _ = try UpdateInstaller.verify(fixtures.appendingPathComponent("same.zip"), into: testSpace.extracted, offer: offer("same.zip", version: running), bundleID: "app.captainlevi.cleaner", running: running) }
            }
            check("lower version refused even when tag agrees") {
                let testSpace = try UpdateWorkspace()
                return refuses { _ = try UpdateInstaller.verify(fixtures.appendingPathComponent("older.zip"), into: testSpace.extracted, offer: offer("older.zip", version: AppVersion("0.9.0")!), bundleID: "app.captainlevi.cleaner", running: running) }
            }
            let trash = workspace.download.appendingPathComponent("Trash")
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
            nonisolated func trashStandIn(_ url: URL) throws -> URL {
                let target = trash.appendingPathComponent(UUID().uuidString + ".app")
                try FileManager.default.moveItem(at: url, to: target)
                return target
            }
            check("failure after trash restores old app") {
                let rejected = refuses { try UpdateInstaller.swap(app, runningApp: installed, trash: { try trashStandIn($0) }, preflight: { _ in }, afterTrash: { throw UpdateFailure.invalidApp }) }
                let siblings = try FileManager.default.contentsOfDirectory(atPath: applications.path)
                let discarded = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
                return rejected && FileManager.default.fileExists(atPath: marker.path)
                    && !siblings.contains { $0.hasPrefix(".levi-update-") } && discarded.count == 1
            }
            check("failed restore retains old and staged apps in Trash without launch app") {
                let launch = applications.appendingPathComponent("Unrestorable.app")
                try FileManager.default.copyItem(at: installed, to: launch)
                let lastResortTrash = workspace.download.appendingPathComponent("LastResortTrash")
                try FileManager.default.createDirectory(at: lastResortTrash, withIntermediateDirectories: false)
                var moved: [URL] = []
                var oldInTrash = false
                do {
                    try UpdateInstaller.swap(app, runningApp: launch, trash: { source in
                        let retained = lastResortTrash.appendingPathComponent(UUID().uuidString + ".app")
                        try FileManager.default.moveItem(at: source, to: retained)
                        moved.append(retained)
                        // Missing returned URL + afterTrash throw makes restore fail;
                        // both the old app and the deferred staged copy stay in Trash.
                        return lastResortTrash.appendingPathComponent("missing-" + UUID().uuidString)
                    }, preflight: { _ in }, afterTrash: { throw UpdateFailure.invalidApp })
                } catch UpdateFailure.oldInTrash { oldInTrash = true }
                catch { note = "oldInTrash=false; moved.count=\(moved.count)"; throw error }
                // Both lists refer to this Trash directory; compare names to ignore
                // symlink spelling (/var vs /private/var) and trailing slashes.
                let retainedAfter = Set(try FileManager.default.contentsOfDirectory(at: lastResortTrash, includingPropertiesForKeys: nil).map { $0.lastPathComponent })
                let siblings = try FileManager.default.contentsOfDirectory(atPath: applications.path)
                note = "oldInTrash=\(oldInTrash); moved.count=\(moved.count)"
                let stagedDigest: String? = moved.count == 2 ? (try? UpdateInstaller.digest(moved[1].appendingPathComponent("Contents/MacOS/fixture"))) : nil
                let sourceDigest = try UpdateInstaller.digest(app.appendingPathComponent("Contents/MacOS/fixture"))
                let conditions: [(String, Bool)] = [
                    ("oldInTrash", oldInTrash), ("twoMoved", moved.count == 2),
                    ("launchAbsent", !FileManager.default.fileExists(atPath: launch.path)),
                    ("retainedMatch", retainedAfter == Set(moved.map { $0.lastPathComponent })),
                    ("oldRetained", moved.first.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("old").path) } ?? false),
                    ("stagedDigestMatches", stagedDigest == sourceDigest),
                    ("sourceExists", FileManager.default.fileExists(atPath: app.path)),
                    ("noStagedSibling", !siblings.contains { $0.hasPrefix(".levi-update-") })
                ]
                note += "; " + conditions.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
                return conditions.allSatisfy { $0.1 }
            }
            check("swap preserves old in Trash and installs new") {
                try UpdateInstaller.swap(app, runningApp: installed, trash: { try trashStandIn($0) }, preflight: { _ in })
                let old = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
                return old.contains { FileManager.default.fileExists(atPath: $0.appendingPathComponent("old").path) }
                    && FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Info.plist").path)
            }
            check("nil Trash URL still installs and retains old") {
                try Data("old".utf8).write(to: marker)
                try UpdateInstaller.swap(app, runningApp: installed, trash: { url in _ = try trashStandIn(url); return nil }, preflight: { _ in })
                let siblings = try FileManager.default.contentsOfDirectory(atPath: applications.path)
                let retained = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
                return FileManager.default.fileExists(atPath: installed.appendingPathComponent("Contents/Info.plist").path)
                    && !siblings.contains { $0.hasPrefix(".levi-update-") }
                    && retained.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("old").path) }.count == 2
            }
            await cancelModel.performCheck(now: Date()) { cancelPayload }
            cancelModel.install { _, _, beginVerification, _ in
                beginVerification()
                cancelModel.cancel() // Disabled during verification/swap.
                withUnsafeCurrentTask { $0?.cancel() } // A late cancelled flag must not hide the real error.
                throw UpdateFailure.oldInTrash("rollback failed")
            }
            for _ in 0..<100 {
                if case .couldNotCheck = cancelModel.state { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            check("late cancel preserves rollback error") {
                guard case .couldNotCheck = cancelModel.state else { return false }
                return cancelModel.errorMessage == "rollback failed" && cancelModel.oldCopyInTrash
            }
            check("translocation exact refusal") {
                do { try UpdateInstaller.preflight(applications.appendingPathComponent("AppTranslocation/X/Captain Levi.app")); return false }
                catch { return error.localizedDescription == "Move Captain Levi to your Applications folder first, then try again." }
            }
            check("unwritable exact refusal") {
                try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
                defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path) }
                do { try UpdateInstaller.preflight(installed, permitted: { _ in true }); return false }
                catch { return error.localizedDescription == "Move Captain Levi to your Applications folder first, then try again." }
            }
            let now = Date()
            var storedDate = now.addingTimeInterval(-23 * 3600)
            var calls = 0
            let payload = Data(#"{"tag_name":"v1.0.0","body":"","draft":false,"prerelease":false,"assets":[]}"#.utf8)
            let model = AppUpdateModel(bundled: true, version: "1.0.0", readLastCheck: { storedDate }, saveLastCheck: { storedDate = $0 })
            await model.checkIfDue(now: now) { calls += 1; return payload }
            check("daily 23h no call") { calls == 0 }
            await model.checkIfDue(now: now.addingTimeInterval(2 * 3600)) { calls += 1; return payload }
            check("daily 25h one call") { calls == 1 }
            let releaseData = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.1.0", "body": String(repeating: "N", count: 700) + "\nSHA-256: \(hash)", "draft": false, "prerelease": false,
                "assets": [["name": "Captain.Levi.zip", "size": 321, "browser_download_url": base.appendingPathComponent("good.zip").absoluteString]]])
            await model.performCheck(now: now) { return releaseData }
            check("check decodes offer and truncates plain notes") {
                guard case .available = model.state else { return false }
                return model.offer?.notes == String(repeating: "N", count: 600) && model.offer?.asset.size == 321
            }
            await model.performCheck(now: now) { throw UpdateFailure.invalidRelease }
            check("check failure preserves offer and reports error") {
                guard case .couldNotCheck = model.state else { return false }
                return model.offer?.asset.size == 321 && model.errorMessage != nil
            }
            let localModel = AppUpdateModel(bundled: false, version: "1.0.0", readLastCheck: { storedDate }, saveLastCheck: { storedDate = $0 })
            await localModel.performCheck(now: now) { calls += 1; return payload }
            await localModel.checkIfDue(now: now.addingTimeInterval(48 * 3600)) { calls += 1; return payload }
            check("non-bundled no call") { calls == 1 && !AppUpdateModel.due(bundled: false, last: nil, now: now) }
            check("missing check is due") { AppUpdateModel.due(bundled: true, last: nil, now: now) }
            withExtendedLifetime(workspace) {}
        } catch { failures += 1; print("FAIL integration fixtures: \(error.localizedDescription)") }
        return failures == 0 ? 0 : 1
    }
}
