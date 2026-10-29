import SwiftUI

// The working screens: what a dry run has found so far, how far a clean has got, which folders a look has been
// through, and the small pieces they share. Motion is short and stops at once under Reduce Motion.

enum Look {
    /// The cool end of the progress gradient (the blue accent is the other end).
    static let teal = Color(red: 0.22, green: 0.74, blue: 0.78)
    static let gradient = LinearGradient(colors: [Color.accentColor, teal], startPoint: .leading, endPoint: .trailing)
}

// MARK: Shared pieces

/// A thin bar that fills from the accent to teal. `fraction` 0...1; it eases to each new value.
struct GradientBar: View {
    var fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule().fill(Look.gradient)
                    .frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: fraction)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

/// A spinner while a step runs, a checkmark that springs in when it is done, a faint ring otherwise.
struct StatusMark: View {
    var finished: Bool
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if finished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Look.teal)
                    .transition(reduceMotion ? .identity : .scale(scale: 0.3).combined(with: .opacity))
            } else if active {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 18, height: 18)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.45), value: finished)
    }
}

/// The newest path, in monospace, ~ for the home folder, cut in the middle; a new one cross-fades in.
struct PathTicker: View {
    var path: String?
    var home: String
    var placeholder = "Waiting for the first item…"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = path.map { $0.abbreviatingHome(home) } ?? placeholder
        ZStack(alignment: .leading) {
            Text(text)
                .id(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: text)
    }
}

/// The fixed strip at the foot of a working screen, styled like the Clean bar.
struct TickerBar: View {
    var symbol: String
    var path: String?
    var home: String
    var placeholder = "Waiting for the first item…"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            PathTicker(path: path, home: home, placeholder: placeholder)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension View {
    /// A rolling-digits change for a number, off under Reduce Motion.
    func rollingNumber(_ value: Double, reduceMotion: Bool) -> some View {
        self
            .contentTransition(reduceMotion ? .identity : .numericText(value: value))
            .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: value)
    }
}

/// A byte count that counts up from 0 as its value is animated (about 1 s), then shows the exact short size.
struct CountingBytes: View, Animatable {
    var value: Double
    var target: Int64
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Int64(value) >= target ? Bytes.short(target) : Bytes.live(Int64(value)))
    }
}

/// "Freed 12.3 GB" with a success symbol that bounces in once and a number that counts up from 0 over about a second.
struct SuccessHeader: View {
    var freed: Int64
    var label = "Freed"
    @State private var shown: Double = 0
    @State private var bounce = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Look.teal)
                .symbolEffect(.bounce, options: .nonRepeating, value: bounce)
            HStack(spacing: 0) {
                Text("\(label) ")
                CountingBytes(value: reduceMotion ? Double(freed) : shown, target: freed)
            }
            .font(.system(size: 30, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
        .onAppear {
            guard !reduceMotion else { return }
            bounce += 1
            withAnimation(.easeOut(duration: 1.0)) { shown = Double(freed) }
        }
    }
}

// MARK: Live dry run

/// A dry run in progress: the running total, a row per section as it turns up, and the newest path.
struct LiveScanView: View {
    var progress: ScanProgress
    var home: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                if progress.sections.isEmpty {
                    Text("Sections appear here as the first items turn up.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
                ForEach(progress.sections) { section in
                    ScanSectionRow(section: section, active: section.raw == progress.active && !section.finished)
                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                header
                    .foregroundStyle(.primary)
                    .textCase(nil)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
            }
        }
        .listStyle(.inset)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: progress.sections.count)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TickerBar(symbol: "doc.text.magnifyingglass", path: progress.latestPath, home: home)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(progress.activeTitle.map { "Looking through \($0)" } ?? "Starting the dry run")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Bytes.live(progress.bytes))
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .rollingNumber(Double(progress.bytes), reduceMotion: reduceMotion)
                Text("found so far").font(.title3).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    Text("\(progress.items.formatted()) \(progress.items == 1 ? "item" : "items")")
                        .rollingNumber(Double(progress.items), reduceMotion: reduceMotion)
                    Text("·")
                    Text("\(Elapsed.text(context.date.timeIntervalSince(progress.startedAt))) elapsed")
                }
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            Text("Nothing is deleted during a dry run.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }
}

private struct ScanSectionRow: View {
    let section: ScanProgress.Section
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            StatusMark(finished: section.finished, active: active)
            Image(systemName: section.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(section.title).font(.headline)
            Spacer(minLength: 16)
            Text("\(section.count.formatted()) \(section.count == 1 ? "item" : "items")")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .rollingNumber(Double(section.count), reduceMotion: reduceMotion)
            Text(Bytes.live(section.bytes))
                .font(.body)
                .monospacedDigit()
                .frame(minWidth: 78, alignment: .trailing)
                .rollingNumber(Double(section.bytes), reduceMotion: reduceMotion)
        }
        .padding(.vertical, 9)
    }
}

// MARK: Live clean

/// A clean, a move to the Trash or a project delete in progress: a determinate bar, the count, what has been freed,
/// the newest path, and a rough time left once enough items are done.
struct LiveCleanView: View {
    var title: String
    /// Follows the big number: "freed so far", "moved to the Trash so far".
    var doneLabel: String
    var note: String
    var progress: CleanProgress
    var home: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(title).font(.callout).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Bytes.live(progress.freedBytes))
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                        .rollingNumber(Double(progress.freedBytes), reduceMotion: reduceMotion)
                    Text(doneLabel).font(.title3).foregroundStyle(.secondary)
                }
            }
            GradientBar(fraction: progress.fraction)
                .padding(.top, 22)
            HStack(alignment: .firstTextBaseline) {
                Text("Item \(progress.processed.formatted()) of \(progress.total.formatted())")
                    .rollingNumber(Double(progress.processed), reduceMotion: reduceMotion)
                Spacer()
                Text("\(Int(progress.fraction * 100))%")
                    .rollingNumber(progress.fraction, reduceMotion: reduceMotion)
            }
            .font(.callout)
            .monospacedDigit()
            .padding(.top, 10)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    Text("\(Elapsed.text(context.date.timeIntervalSince(progress.startedAt))) elapsed")
                    if let left = progress.secondsLeft(now: context.date) {
                        Text("·")
                        Text(Elapsed.left(left))
                    }
                    if progress.leftAlone > 0 {
                        Text("·")
                        Text("\(progress.leftAlone.formatted()) left alone")
                    }
                }
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TickerBar(symbol: "trash", path: progress.latestPath, home: home)
        }
    }
}

// MARK: Live project look

/// The look for old build folders: the folders it has been through (checkmarks) and the one it is in now.
struct ProjectsLookView: View {
    var progress: ProjectsLookProgress
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                ForEach(rows, id: \.name) { row in
                    HStack(spacing: 12) {
                        StatusMark(finished: row.done, active: !row.done)
                        Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 20)
                        Text(row.name).font(.headline)
                        Spacer()
                        if !row.done { Text("looking…").font(.callout).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 6)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(progress.current.map { "Looking in \($0)" } ?? "Starting the look")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("Looking for old build folders")
                        .font(.system(size: 30, weight: .bold))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 6) {
                            Text("\(progress.finished.count) \(progress.finished.count == 1 ? "folder" : "folders") looked through")
                                .rollingNumber(Double(progress.finished.count), reduceMotion: reduceMotion)
                            Text("·")
                            Text("\(Elapsed.text(context.date.timeIntervalSince(progress.startedAt))) elapsed")
                        }
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                    Text("Nothing is deleted while it looks.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }
        }
        .listStyle(.inset)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: rows.count)
    }

    private var rows: [(name: String, done: Bool)] {
        progress.finished.map { ($0, true) } + (progress.current.map { [($0, false)] } ?? [])
    }
}
