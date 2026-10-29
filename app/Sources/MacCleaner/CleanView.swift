import SwiftUI

/// The Clean screen: a dry run first, then what it found, grouped as Mole groups it, with one button to clean
/// what is ticked; then the result.
struct CleanView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                StartView { Task { await model.scan() } }
            case .scanning:
                LiveScanView(progress: model.scanProgress, home: model.home)
            case .reviewing:
                if let plan = Binding($model.plan) {
                    ReviewView(plan: plan, home: model.home, onScan: { Task { await model.scan() } },
                               onClean: { model.confirming = true })
                        .sheet(isPresented: $model.confirming) {
                            ConfirmSheet(plan: plan.wrappedValue, onCancel: { model.confirming = false },
                                         onConfirm: { Task { await model.clean() } })
                        }
                }
            case .cleaning:
                LiveCleanView(title: "Cleaning what you ticked…", doneLabel: "freed so far",
                              note: "Each item is checked again just before it goes.",
                              progress: model.cleanProgress, home: model.home)
            case .done(let freed, let cleaned, let skipped):
                DoneView(freed: freed, cleaned: cleaned, skipped: skipped, home: model.home) { Task { await model.scan() } }
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "That didn't work", detail: message,
                            button: "Try again") { Task { await model.scan() } }
            }
        }
        .toolbar(removing: .title)
    }
}

private struct StartView: View {
    var onScan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("See what can be cleaned")
                .font(.system(size: 30, weight: .bold))
            Text("A dry run looks through caches and logs and lists everything that could go, with sizes. Nothing is deleted until you tick it and confirm.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onScan) {
                Text("Run a dry run").padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
            Label("The first time, macOS may ask whether Captain Levi can access data from other apps. That lets it measure caches kept inside other apps' folders. Either answer is fine: with Don't Allow, those caches are skipped.",
                  systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct WorkingView: View {
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView().controlSize(.large)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MessageView: View {
    var symbol: String
    var title: String
    var detail: String
    var button: String
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(button, action: action).controlSize(.large).padding(.top, 6)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DoneView: View {
    var freed: Int64
    var cleaned: Int
    var skipped: [ApplyResult]
    var home: String
    var onScan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SuccessHeader(freed: freed)
                Text("\(cleaned) \(cleaned == 1 ? "item" : "items") removed. Each one is listed in History.")
                    .foregroundStyle(.secondary)
                if !skipped.isEmpty {
                    Text("Left alone (\(skipped.count))").font(.headline).padding(.top, 10)
                    ForEach(skipped, id: \.self) { result in
                        HStack(alignment: .firstTextBaseline) {
                            Text(result.path.abbreviatingHome(home))
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(result.reason).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Run another dry run", action: onScan)
                    .controlSize(.large)
                    .padding(.top, 10)
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ReviewView: View {
    @Binding var plan: CleanPlan
    var home: String
    var onScan: () -> Void
    var onClean: () -> Void

    var body: some View {
        List {
            Section {
                if plan.groups.isEmpty {
                    Text("Nothing to clean right now.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                ForEach($plan.groups) { $group in
                    GroupRow(group: $group)
                    if group.expanded {
                        ForEach(group.visibleIndices, id: \.self) { index in
                            ItemRow(item: $group.items[index], home: home)
                        }
                        if group.hiddenCount > 0 {
                            Button("Show \(group.hiddenCount) more (\(Bytes.short(group.hiddenBytes)))") {
                                group.showAll = true
                            }
                            .buttonStyle(.link)
                            .font(.callout)
                            .padding(.leading, 64)
                        }
                    }
                }
            } header: {
                Header(plan: plan)
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanBar(plan: plan, onScan: onScan, onClean: onClean)
        }
    }
}

private struct Header: View {
    let plan: CleanPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(Bytes.short(plan.foundBytes)) can be freed")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
            Text("Found by a dry run at \(plan.scannedAt.formatted(date: .omitted, time: .shortened)). Nothing has been deleted.")
                .font(.body)
                .foregroundStyle(.secondary)
            if plan.diskTotalBytes > 0 {
                DiskBar(plan: plan).padding(.top, 6)
            }
        }
        .textCase(nil)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

/// Free space now, and after cleaning what is ticked: the number that says what cleaning is worth.
private struct DiskBar: View {
    let plan: CleanPlan

    var body: some View {
        let free = Double(plan.diskFreeBytes)
        let gain = Double(plan.selectedBytes)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(Color.secondary.opacity(0.45))
                        .frame(width: geo.size.width * free / max(free + gain, 1))
                    Rectangle().fill(Color.accentColor)
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 8)
            Text(plan.selectedBytes < 50_000_000
                 ? "Free space now: \(Bytes.short(plan.diskFreeBytes))"
                 : "Free space goes from \(Bytes.short(plan.diskFreeBytes)) to \(Bytes.short(plan.diskFreeBytes + plan.selectedBytes)) when you clean what is ticked")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

private struct GroupRow: View {
    @Binding var group: CleanGroup

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { group.isSelected },
                set: { on in
                    for i in group.items.indices where group.items[i].skippedReason == nil {
                        group.items[i].selected = on
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Image(systemName: group.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(group.title).font(.headline)
                    CautionTag(caution: group.caution)
                }
                Text(group.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(Bytes.short(group.bytes))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(group.isSelected ? .primary : .secondary)

            Button {
                group.expanded.toggle()
            } label: {
                Image(systemName: group.expanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help(group.expanded ? "Hide the items" : "Show the \(group.items.count) items")
        }
        .padding(.vertical, 6)
    }
}

private struct CautionTag: View {
    let caution: Caution

    var body: some View {
        switch caution {
        case .none:
            EmptyView()
        case .needsPassword:
            Label("Asks for your Mac password", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .yourFiles:
            Label("Your files, not caches", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        }
    }
}

private struct ItemRow: View {
    @Binding var item: CleanItem
    var home: String

    var body: some View {
        HStack(spacing: 10) {
            if item.skippedReason == nil {
                Toggle("", isOn: $item.selected)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            } else {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(item.path.abbreviatingHome(home))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.skippedReason == nil ? .primary : .secondary)
                .help(item.path)
            if let note = item.note ?? item.skippedReason {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            Text(Bytes.short(item.bytes))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.trailing, 28)
        }
        .padding(.leading, 64)
        .padding(.vertical, 1)
    }
}

/// Fixed bar: how much is ticked, and the one bright button.
struct CleanBar: View {
    let plan: CleanPlan
    var onScan: () -> Void
    var onClean: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(plan.selectedGroupCount) of \(plan.groups.count) groups ticked")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Scan again", action: onScan)
                .controlSize(.large)
                .help("Run a new dry run. Nothing is deleted.")
            Button(action: onClean) {
                Text("Clean \(Bytes.short(plan.selectedBytes))…")
                    .monospacedDigit()
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(plan.selectedBytes == 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
