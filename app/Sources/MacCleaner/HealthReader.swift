import AppKit
import Foundation
import IOKit.ps

/// Reads the Mac's health for the menu bar card. Everything here is read without asking macOS for any permission: disk space,
/// memory pressure, battery, processor load and which drives are plugged in (names only; no drive's files are opened).
@MainActor
final class HealthReader: ObservableObject {
    @Published private(set) var health = MenuBarHealth(diskFree: 0, diskTotal: 1, memoryPressure: 0, batteryPercent: nil,
                                                       charging: false, cpuLoad: 0, externalDrives: [], reclaimable: nil)
    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?

    /// Starts reading every few seconds. The card is a menu bar window, so this runs for the life of the app; each read is a few
    /// system calls.
    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(reclaimable: Int64? = nil) {
        let disk = Self.disk()
        let battery = Self.battery()
        health = MenuBarHealth(diskFree: disk.free, diskTotal: disk.total, memoryPressure: Self.memoryPressure(),
                               batteryPercent: battery?.percent, charging: battery?.charging ?? false, cpuLoad: cpuLoad(),
                               externalDrives: Self.externalDrives(), reclaimable: reclaimable ?? health.reclaimable)
    }

    func setReclaimable(_ bytes: Int64?) { health.reclaimable = bytes }

    private static func disk() -> (free: Int64, total: Int64) {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return (0, 1) }
        return (values.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values.volumeTotalCapacity ?? 1))
    }

    /// The share of memory under pressure: 100 minus the system's own "memory free" percentage.
    private static func memoryPressure() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return 0 }
        return max(0, min(100, 100 - Int(level)))
    }

    private static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return (current * 100 / maximum, charging)
        }
        return nil
    }

    /// Busy share of all processors since the last read.
    private func cpuLoad() -> Int {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice, total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return 0 }
        return Int(Double(busy - last.busy) / Double(total - last.total) * 100)
    }

    /// Names of plugged-in drives (not the startup disk, not network shares).
    private static func externalDrives() -> [String] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard url.path.hasPrefix("/Volumes/"), let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsLocal == true, values.volumeIsInternal == false else { return nil }
            return values.volumeName
        }
    }
}
