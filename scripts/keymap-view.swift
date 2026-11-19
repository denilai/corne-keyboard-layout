// KeymapView.app: shows the keymap picture in front of other windows (macOS).
//
//   KeymapView <file.svg>      (scripts/keymap-view.sh builds and starts it)
//
// Quick Look started from a background process (the Karabiner rule) opens
// without focus, and bringing it forward needs Accessibility permission. An
// app started with `open` is activated by macOS itself, so this tiny viewer
// takes focus. The SVG is drawn by WebKit: the system SVG renderer of NSImage
// ignores its CSS (colors, fonts, multi-line labels).
//
// Window: picture width, up to the screen height, scrolls. Esc, Cmd+W or the
// close button quits; scripts/keymap-view.sh toggle quits it too.
import AppKit
import WebKit

final class Window: NSWindow {
    override func keyDown(with e: NSEvent) {
        let cmdW = e.modifierFlags.contains(.command) && e.charactersIgnoringModifiers == "w"
        if e.keyCode == 53 || cmdW { NSApp.terminate(nil) } else { super.keyDown(with: e) }
    }
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.modifierFlags.contains(.command) && e.charactersIgnoringModifiers == "w" {
            NSApp.terminate(nil)
        }
        return super.performKeyEquivalent(with: e)
    }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: Window!

    func applicationDidFinishLaunching(_ n: Notification) {
        let path = CommandLine.arguments.dropFirst().first ?? ""
        let url = URL(fileURLWithPath: path)
        // Picture size from the SVG (NSImage reads the size fine), fit to screen.
        let size = NSImage(contentsOf: url)?.size ?? NSSize(width: 900, height: 1200)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = min(size.width, screen.width - 40)
        let h = min(size.height, screen.height - 40)
        window = Window(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Corne keymap"
        window.delegate = self
        let web = WKWebView(frame: window.contentView!.bounds)
        web.autoresizingMask = [.width, .height]
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        window.contentView!.addSubview(web)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ n: Notification) { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon; `open` still activates it
let delegate = App()
app.delegate = delegate
app.run()
