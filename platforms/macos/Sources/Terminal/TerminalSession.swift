import Foundation
import SwiftTerm
import AppKit

@MainActor
public class TerminalSession: ObservableObject, TerminalViewDelegate, InteractiveSSHChannelDelegate {
    public let terminalView: TerminalView
    private let sshChannel: InteractiveSSHChannel
    private nonisolated(unsafe) var ptyStarted = false
    
    public init(connection: SSHConnection) throws {
        self.terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 450))
        self.sshChannel = try InteractiveSSHChannel(connection: connection)
        
        self.terminalView.terminalDelegate = self
        self.sshChannel.delegate = self
    }
    
    /// Call this after the view is embedded. The actual PTY allocation
    /// is deferred until the first sizeChanged callback so the column
    /// count matches the real laid-out view.
    public func start() {
        // PTY will be started on first sizeChanged when view is laid out
    }
    
    private func startPtyIfNeeded(cols: Int, rows: Int) {
        guard !ptyStarted else { return }
        ptyStarted = true
        
        do {
            try sshChannel.requestPtyAndShell(
                terminal: "xterm-256color",
                columns: cols,
                rows: rows
            )
            sshChannel.startReading()
        } catch {
            print("PTY start failed: \(error)")
        }
    }
    
    public func stop() {
        sshChannel.close()
    }
    
    // MARK: - InteractiveSSHChannelDelegate
    
    nonisolated public func channel(_ channel: InteractiveSSHChannel, didReceiveData data: Data) {
        let array = [UInt8](data)
        Task { @MainActor in
            self.terminalView.feed(byteArray: array[...])
        }
    }
    
    nonisolated public func channelDidClose(_ channel: InteractiveSSHChannel) {}
    
    // MARK: - TerminalViewDelegate
    
    nonisolated public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        sshChannel.write(data: Data(data))
    }
    
    nonisolated public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        guard newCols > 0, newRows > 0 else { return }
        
        if !ptyStarted {
            // First valid size → start PTY with correct dimensions
            Task { @MainActor in
                self.startPtyIfNeeded(cols: newCols, rows: newRows)
            }
        } else {
            sshChannel.setWindowSize(columns: newCols, rows: newRows)
        }
    }
    
    nonisolated public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
    nonisolated public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
    
    nonisolated public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        if let string = String(data: content, encoding: .utf8) {
            Task { @MainActor in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(string, forType: .string)
            }
        }
    }
    
    nonisolated public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
    nonisolated public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
}
