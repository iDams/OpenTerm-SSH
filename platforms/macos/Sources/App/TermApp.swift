import SwiftUI

@main
struct OpenTermApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About OpenTerm SSH") {
                    AboutWindowController.shared.showWindow()
                }
            }
        }
    }
}

class AboutWindowController {
    static let shared = AboutWindowController()
    private var window: NSWindow?

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let view = AboutView()
        let hostingController = NSHostingController(rootView: view)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.center()
        newWindow.title = "About OpenTerm SSH"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
