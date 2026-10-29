import SwiftUI

/// A printable, one-page insert. All illustrations are symbols, not Settings screenshots.
struct FirstOpenGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Opening Captain Levi the first time")
                    .font(.system(size: 44, weight: .bold))
                Text("macOS asks once, because the app is not from the App Store. It takes about a minute.")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            step(1, title: "Open the app",
                 sentence: "Double-click Captain Levi. macOS says it cannot be opened. Click Done.", symbol: "app.dashed")
            step(2, title: "Open System Settings",
                 sentence: "Go to Privacy & Security and scroll down to Security. Next to Captain Levi, click Open Anyway.", symbol: "gearshape")
            step(3, title: "Confirm",
                 sentence: "Enter your Mac's password if it asks, then click Open. This only happens the first time. Updates inside the app never ask again.", symbol: "checkmark.seal")

            Spacer(minLength: 0)
            Text("Made from Mole (GPL-3.0). Questions: open an issue on the project's GitHub page.")
                .font(.system(size: 19)).foregroundStyle(.secondary)
        }
        .padding(64)
        .frame(width: 1600, height: 1000, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func step(_ number: Int, title: String, sentence: String, symbol: String) -> some View {
        HStack(spacing: 28) {
            Text("\(number)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .frame(width: 68)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(size: 27, weight: .semibold))
                Text(sentence).font(.system(size: 22)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Image(systemName: symbol)
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.green)
                .frame(width: 88)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.green.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.green.opacity(0.20)))
    }
}
