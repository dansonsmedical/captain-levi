import AppKit
import SwiftUI

/// Renders views into PNGs in-process, without showing anything on screen and without any screen-capture API:
/// the window sits far off every display and its layer tree is drawn straight into a bitmap. (A window-server
/// capture can make macOS ask the user to allow screen recording; never use one here.)
/// Limitation: see-through materials such as the sidebar's glass draw as plain white or black.
@MainActor
enum MockRenderer {
    static func render<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL,
                                pixelSize: CGSize? = nil) throws {
        let host = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
        let window = KeyLookWindow(contentRect: NSRect(x: -6000, y: -6000, width: size.width, height: size.height),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                   backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.title = "Captain Levi"
        if let pixelSize {
            // New picture exports include the title bar inside their stated dimensions.
            // Preserve the existing --render sizing and 2x output when this is omitted.
            window.setFrame(NSRect(x: -6000, y: -6000, width: pixelSize.width, height: pixelSize.height), display: false)
        }
        window.contentView = host
        // Never ordered on screen: the view is laid out and drawn in this window's layers only.
        host.layoutSubtreeIfNeeded()
        host.display()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()
        host.display()
        CATransaction.flush()
        guard let layer = window.contentView?.superview?.layer ?? host.layer else {
            throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "no layer to draw"])
        }
        try write(layer, to: url, pixelSize: pixelSize)
    }

    /// Draws standalone SwiftUI artwork at one pixel per point, with no window chrome.
    static func artwork<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var png: Data?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: size.width, height: size.height))
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
            if let image = renderer.cgImage {
                png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
        }
        guard let png else {
            throw NSError(domain: "render", code: 4, userInfo: [NSLocalizedDescriptionKey: "no artwork image"])
        }
        try png.write(to: url)
    }

    /// Draws a window of the running app into a PNG from its own layers (no screen capture).
    static func snapshot(of window: NSWindow, to url: URL) throws {
        guard let layer = window.contentView?.superview?.layer ?? window.contentView?.layer else {
            throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "no layer to draw"])
        }
        try write(layer, to: url)
    }

    private static func write(_ layer: CALayer, to url: URL, pixelSize: CGSize? = nil) throws {
        let scale: CGFloat = 2
        let w = Int(pixelSize?.width ?? layer.bounds.width * scale)
        let h = Int(pixelSize?.height ?? layer.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "render", code: 2, userInfo: [NSLocalizedDescriptionKey: "no bitmap"])
        }
        ctx.scaleBy(x: pixelSize == nil ? scale : CGFloat(w) / layer.bounds.width,
                    y: pixelSize == nil ? scale : CGFloat(h) / layer.bounds.height)
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else {
            throw NSError(domain: "render", code: 3, userInfo: [NSLocalizedDescriptionKey: "no image"])
        }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
    }
}

/// Draws as the active window so controls show their real colours, without taking focus from the user's apps.
final class KeyLookWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}

/// Reports itself active so AppKit draws controls in their active colours during a render.
final class ActiveLookApplication: NSApplication {
    override var isActive: Bool { true }
}
