# Captain Levi

Captain Levi is a Mac cleaner that looks first and deletes only what you tick.
Apps and old installers move to the Trash so you can put them back.
Requires Apple Silicon and macOS 15 or later.

Download the zip from the [Releases page](https://github.com/dansonsmedical/captain-levi/releases),
unzip it and move Captain Levi.app to Applications.

1. Open Captain Levi. If macOS blocks it, click Done.
2. Open System Settings → Privacy & Security → Security → Open Anyway.
3. Enter your Mac password if asked, then click Open.

Captain Levi asks GitHub for a newer release at most once a day when opened.
It installs an update only when you click Install update.

Captain Levi is modified from Mole (github.com/tw93/mole), October 2026.
Made from [Mole](https://github.com/tw93/mole), licensed under GPL-3.0.
Build from source with SwiftPM: run app/build.sh --release on a Mac with the Swift tools.
The app is written to app/build/Captain Levi.app.
For historical reasons, the app keeps its data in `~/Library/Application Support/Mac Cleaner`.

This source and its changes are licensed under GPL-3.0; see [LICENSE](LICENSE).
Captain Levi is not affiliated with or endorsed by Mole. See [TRADEMARK.md](TRADEMARK.md).
