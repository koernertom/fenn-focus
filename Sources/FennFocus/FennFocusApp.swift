import SwiftUI
import AppKit
import FennFocusCore

/// Fenn lives in the notch island (no Dock icon, LSUIElement) and opens a normal window on demand.
@main
struct FennFocusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                // LSUIElement apps often miss the system Quit item — keep ⌘Q explicit.
                CommandGroup(replacing: .appTermination) {
                    Button(tr("Fenn Focus beenden", "Quit Fenn Focus")) { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var island: IslandController?
    private var quitMonitor: Any?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { island?.open(url) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Fenn's palette is dark-canvas only — materials must render dark regardless of the system setting.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        installQuitMenu()
        installQuitShortcut()

        let island = IslandController()
        island.show()
        self.island = island
    }

    /// Clicking Fenn in the Dock (while its window is open) or opening it again from Finder shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        island?.openWindow()
        return true
    }

    /// Minimal app menu so ⌘Q is wired even without a Dock icon / full SwiftUI WindowGroup.
    private func installQuitMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "Fenn Focus")
        let quit = NSMenuItem(
            title: tr("Fenn Focus beenden", "Quit Fenn Focus"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    /// Island panel is nonactivating — menu key equivalents can miss. Local ⌘Q always quits while Fenn is key.
    private func installQuitShortcut() {
        quitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "q" else { return event }
            NSApp.terminate(nil)
            return nil
        }
    }
}
