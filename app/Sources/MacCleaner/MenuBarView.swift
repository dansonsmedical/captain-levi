import AppKit
import SwiftUI

/// What the menu bar icon shows: the Mac's health at a glance and one button for the main thing to do. Every number here is read
/// without asking macOS for any permission (disk space, memory pressure, battery, processor load, drives).
struct MenuBarHealth {
    var diskFree: Int64
    var diskTotal: Int64
    var memoryPressure: Int
    var batteryPercent: Int?
    var charging: Bool
    var cpuLoad: Int
    var externalDrives: [String]
    var reclaimable: Int64?

    var lowDisk: Bool { Double(diskFree) / Double(max(diskTotal, 1)) < 0.12 }
    var summary: String { lowDisk || memoryPressure > 75 ? "Needs attention" : "Good" }
}

struct MenuBarView: View {
    var health: MenuBarHealth
    /// Opens Captain Levi on the Clean pane and starts a look (a look deletes nothing).
    var lookToClean: () -> Void = {}
    var openApp: () -> Void = {}

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Mac health: ").foregroundStyle(.primary)
                        + Text(health.summary).foregroundStyle(health.summary == "Good" ? Color.green : Color.orange))
                        .font(.title3.weight(.semibold))
                    Text("Updated just now").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "laptopcomputer").font(.system(size: 26)).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                Tile(symbol: "internaldrive", title: "Macintosh HD",
                     line: "\(Bytes.short(health.diskFree)) free of \(Bytes.short(health.diskTotal))",
                     tint: health.lowDisk ? .orange : .primary, action: health.lowDisk ? "Free up…" : nil, perform: lookToClean)
                Tile(symbol: "memorychip", title: "Memory", line: "Pressure \(health.memoryPressure)%",
                     tint: health.memoryPressure > 75 ? .orange : .primary, action: nil)
                Tile(symbol: health.charging ? "battery.100.bolt" : "battery.75", title: "Battery",
                     line: health.batteryPercent.map { "\($0)%" + (health.charging ? ", charging" : "") } ?? "No battery",
                     tint: .primary, action: nil)
                Tile(symbol: "cpu", title: "Processor", line: "Load \(health.cpuLoad)%", tint: .primary, action: nil)
            }
            Tile(symbol: "externaldrive", title: "External drives",
                 line: health.externalDrives.isEmpty ? "None connected" : health.externalDrives.joined(separator: ", "),
                 tint: .primary, action: nil)

            do {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's suggestion").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(health.reclaimable.map { "\(Bytes.short($0)) can be cleaned" } ?? "Look for what can be cleaned").font(.headline)
                            Text("Caches, logs and old installers. You look at every item first; nothing is deleted from here.")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Look at what to clean", action: lookToClean).buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 4)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5)))
                }
            }

            Divider()
            HStack {
                Button(action: openApp) { Label("Open Captain Levi", systemImage: "arrow.up.forward.app") }.buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 360)
        .background(.regularMaterial)
    }
}

private struct Tile: View {
    var symbol: String
    var title: String
    var line: String
    var tint: Color
    var action: String?
    var perform: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text(line).font(.callout).foregroundStyle(tint == .primary ? .secondary : tint).fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: perform) { Text(action).font(.callout.weight(.medium)) }
                    .buttonStyle(.plain).foregroundStyle(.tint).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }
}

extension Fixtures {
    static var health: MenuBarHealth {
        MenuBarHealth(diskFree: 38_000_000_000, diskTotal: 494_000_000_000, memoryPressure: 64, batteryPercent: 98, charging: true,
                      cpuLoad: 31, externalDrives: [], reclaimable: 12_300_000_000)
    }
}
