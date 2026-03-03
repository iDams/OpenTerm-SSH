import SwiftUI
import SwiftTerm
import AppKit

private let sshTerminalDebugEnabled = ProcessInfo.processInfo.environment["OPENTERM_DEBUG_TERMINAL"] == "1"

private func sshTerminalDebug(_ message: @autoclosure () -> String) {
    guard sshTerminalDebugEnabled else { return }
    print("[SSHTerminal] \(message())")
}

/// NSViewRepresentable that embeds a TerminalView for SSH sessions.
/// Follows the same pattern as NotchTerminal's SwiftTermContainerView:
/// the TerminalView itself is the NSView, with a Coordinator for delegates.
struct SSHTerminalContainerView: NSViewRepresentable {
    let connection: SSHConnection
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        
        let terminal = TerminalView(frame: .zero)
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
        
        context.coordinator.connection = connection
        context.coordinator.tryStartIfNeeded(on: terminal)
        
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let terminal = nsView.subviews.first(where: { $0 is TerminalView }) as? TerminalView else { return }
        if nsView.window?.firstResponder !== terminal {
            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
        context.coordinator.tryStartIfNeeded(on: terminal)
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }
    
    final class Coordinator: NSObject, TerminalViewDelegate, InteractiveSSHChannelDelegate {
        var connection: SSHConnection?
        private var channel: InteractiveSSHChannel?
        private var started = false
        private var ptyStarted = false
        private var retryScheduled = false
        
        func tryStartIfNeeded(on terminal: TerminalView) {
            guard !started else { return }
            
            // Wait until the view has a real size (same pattern as NotchTerminal)
            if terminal.window != nil, terminal.bounds.width > 120, terminal.bounds.height > 90 {
                startSSH(on: terminal)
                return
            }
            
            guard !retryScheduled else { return }
            retryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak terminal] in
                guard let self else { return }
                self.retryScheduled = false
                guard let terminal else { return }
                self.tryStartIfNeeded(on: terminal)
            }
        }
        
        private func startSSH(on terminal: TerminalView) {
            guard let connection else { return }
            started = true
            
            terminal.terminalDelegate = self
            self.terminalView = terminal
            
            do {
                let sshChannel = try InteractiveSSHChannel(connection: connection)
                sshChannel.delegate = self
                self.channel = sshChannel

                sshTerminalDebug("terminal ready bounds=\(terminal.bounds.size) cols=\(terminal.getTerminal().cols) rows=\(terminal.getTerminal().rows)")

                // Let SwiftTerm finish layout first. The real PTY size will be
                // negotiated from the first sizeChanged callback when possible.
                // Some layouts do not emit that callback immediately, so we
                // also perform a delayed fallback start using the current size.
                DispatchQueue.main.async {
                    terminal.getTerminal().updateFullScreen()
                    terminal.setNeedsDisplay(terminal.bounds)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak terminal] in
                    guard let self, let terminal else { return }
                    let cols = max(terminal.getTerminal().cols, 20)
                    let rows = max(terminal.getTerminal().rows, 5)
                    sshTerminalDebug("fallback start cols=\(cols) rows=\(rows)")
                    self.beginInteractiveSessionIfNeeded(columns: cols, rows: rows)
                }
            } catch {
                print("[SSHTerminal] Failed to start: \(error)")
            }
        }

        private func beginInteractiveSessionIfNeeded(columns: Int, rows: Int) {
            guard let channel, !ptyStarted else { return }

            do {
                sshTerminalDebug("requestPtyAndShell cols=\(columns) rows=\(rows)")
                try channel.requestPtyAndShell(
                    terminal: "xterm-256color",
                    columns: max(columns, 20),
                    rows: max(rows, 5)
                )
                channel.startReading()
                ptyStarted = true
            } catch {
                print("[SSHTerminal] Failed to request PTY/shell: \(error)")
            }
        }
        
        func stop() {
            channel?.close()
            channel = nil
            ptyStarted = false
        }
        
        // MARK: - InteractiveSSHChannelDelegate
        
        func channel(_ channel: InteractiveSSHChannel, didReceiveData data: Data) {
            let bytes = [UInt8](data)
            sshTerminalDebug("recv bytes=\(bytes.count) preview=\(String(decoding: data.prefix(80), as: UTF8.self).replacingOccurrences(of: "\u{1b}", with: "<esc>"))")
            DispatchQueue.main.async { [weak self] in
                self?.terminalView?.feed(byteArray: bytes[...])
            }
        }
        
        func channelDidClose(_ channel: InteractiveSSHChannel) {}
        
        // Weak ref to terminal for feeding data
        weak var terminalView: TerminalView?
        
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let outbound = Data(data)
            sshTerminalDebug("send bytes=\(outbound.count) hex=\(outbound.map { String(format: "%02x", $0) }.joined(separator: " "))")
            channel?.write(data: Data(data))
        }
        
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            sshTerminalDebug("sizeChanged cols=\(newCols) rows=\(newRows)")
            beginInteractiveSessionIfNeeded(columns: newCols, rows: newRows)
            channel?.setWindowSize(columns: newCols, rows: newRows)
        }
        
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        
        func clipboardCopy(source: TerminalView, content: Data) {
            if let string = String(data: content, encoding: .utf8) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(string, forType: .string)
            }
        }
        
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

struct PersistentTerminalSessionContainerView: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    
    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        attachTerminal(to: container)
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        attachTerminal(to: nsView)
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        sessionCleanup(nsView: nsView)
    }
    
    private static func sessionCleanup(nsView: NSView) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
    }
    
    private func attachTerminal(to container: NSView) {
        let terminal = session.terminalView
        
        // Ensure the reused NSView only ever hosts the active session's terminal.
        container.subviews
            .filter { $0 !== terminal }
            .forEach { staleView in
                staleView.removeFromSuperview()
            }
        
        if terminal.superview !== container {
            terminal.removeFromSuperview()
            terminal.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminal)
            NSLayoutConstraint.activate([
                terminal.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
                terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
            ])
        }
        
        if container.window?.firstResponder !== terminal {
            DispatchQueue.main.async {
                terminal.window?.makeFirstResponder(terminal)
            }
        }
        
        session.start()
    }
}
