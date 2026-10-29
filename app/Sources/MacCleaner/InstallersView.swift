import SwiftUI

/// Old installer files in Downloads and Desktop, moved to the Trash (so they can be put back) on the user's click.
struct InstallersView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            switch model.installersState {
            case .notLooked:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Old installers").font(.system(size: 30, weight: .bold))
                    Text("Disk images and installers (.dmg, .pkg, .iso, .xip) left in your Downloads and Desktop after you installed an app. Nothing is ticked for you, and what you tick goes to the Trash, so you can put it back.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task { await model.findInstallers() }
                    } label: {
                        Text("Look in Downloads and Desktop").padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
                    Label("macOS will ask once whether Captain Levi may see your Downloads and Desktop folders. Allow lets it list the installers there; nothing else in those folders is touched.",
                          systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .looking:
                WorkingView(title: "Looking for installers…", detail: "Only Downloads and Desktop, one folder deep.")
            case .moving:
                LiveCleanView(title: "Moving to the Trash…", doneLabel: "moved to the Trash so far",
                              note: "You can put them back from the Trash.",
                              progress: model.cleanProgress, home: model.home)
            case .found:
                foundList
            case .done(let moved, let freed, let skipped):
                MessageView(symbol: "trash", title: "\(moved) moved to the Trash",
                            detail: "\(Bytes.short(freed)) will be freed when you empty the Trash. \(skipped.isEmpty ? "" : "\(skipped.count) left where they were.")",
                            button: "Look again") { Task { await model.findInstallers() } }
            case .failed(let message):
                MessageView(symbol: "exclamationmark.triangle", title: "That didn't work", detail: message,
                            button: "Try again") { Task { await model.findInstallers() } }
            }
        }
        .toolbar(removing: .title)
    }

    private var foundList: some View {
        List {
            Section {
                if model.installers.isEmpty {
                    Text("No old installers in Downloads or Desktop.").foregroundStyle(.secondary).padding(.vertical, 8)
                }
                ForEach($model.installers) { $item in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox)
                        Text(item.path.abbreviatingHome(model.home))
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                            .help(item.path)
                        Spacer(minLength: 16)
                        Text(Bytes.short(item.bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(model.installers.count) old \(model.installers.count == 1 ? "installer" : "installers")")
                        .font(.system(size: 30, weight: .bold))
                    Text("Tick the ones you no longer need. They go to the Trash.").foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.vertical, 14)
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            let ticked = model.installers.filter(\.selected)
            HStack {
                Text("\(ticked.count) ticked").foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.confirmingInstallers = true
                } label: {
                    Text("Move \(Bytes.short(ticked.reduce(0) { $0 + $1.bytes })) to the Trash…").monospacedDigit().padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(ticked.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .confirmationDialog("Move the ticked installers to the Trash?", isPresented: $model.confirmingInstallers) {
            Button("Move to the Trash") { Task { await model.moveInstallersToTrash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can put them back from the Trash until you empty it.")
        }
    }
}
