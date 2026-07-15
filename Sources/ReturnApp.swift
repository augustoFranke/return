import AppKit
import SwiftUI

@main
struct ReturnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = AudioMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor)
                .onAppear { appDelegate.monitor = monitor }
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    /// MenuBarExtra ignores `.font()` on SF Symbols — render into a sized NSImage.
    private static let menuBarIcon: NSImage = {
        let pointSize: CGFloat = 16
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard var symbol = NSImage(systemSymbolName: "microphone.circle.fill", accessibilityDescription: "Return")?
            .withSymbolConfiguration(config) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        symbol.isTemplate = true
        symbol.size = NSSize(width: pointSize, height: pointSize)
        return symbol
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var monitor: AudioMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
    }
}
