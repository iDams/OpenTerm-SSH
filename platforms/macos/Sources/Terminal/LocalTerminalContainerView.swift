import SwiftUI
import SwiftTerm
import AppKit

struct LocalTerminalContainerView: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.wantsLayer = true
        terminal.layer?.backgroundColor = NSColor.black.cgColor
        terminal.nativeBackgroundColor = .black
        terminal.nativeForegroundColor = .white
        let defaultFonts = ["MesloLGS Nerd Font", "Hack Nerd Font", "FiraCode Nerd Font", "Menlo Regular"]
        terminal.font = defaultFonts.compactMap { NSFont(name: $0, size: 13) }.first ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        
        terminal.processDelegate = context.coordinator
        
        context.coordinator.tryStartProcessIfNeeded(on: terminal)
        
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
        
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let terminal = nsView.subviews.first(where: { $0 is LocalProcessTerminalView }) as? LocalProcessTerminalView else { return }
        
        context.coordinator.tryStartProcessIfNeeded(on: terminal)
        
        if nsView.window?.firstResponder !== terminal {
            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        guard let terminal = nsView.subviews.first(where: { $0 is LocalProcessTerminalView }) as? LocalProcessTerminalView else { return }
        terminal.terminate()
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var processStarted = false
        var startRetryScheduled = false

        func tryStartProcessIfNeeded(on terminal: LocalProcessTerminalView) {
            guard !processStarted else { return }

            if terminal.window != nil, terminal.bounds.width > 50, terminal.bounds.height > 50 {
                let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                terminal.startProcess(executable: shell, args: ["-l"])
                processStarted = true
                return
            }

            guard !startRetryScheduled else { return }
            startRetryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak terminal] in
                guard let self else { return }
                self.startRetryScheduled = false
                guard let terminal else { return }
                self.tryStartProcessIfNeeded(on: terminal)
            }
        }
        
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
