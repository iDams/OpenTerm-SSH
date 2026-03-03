import SwiftUI
import Observation
import UniformTypeIdentifiers

private struct TransferDragPayload: Codable {
    let sourcePaneID: UUID
    let itemPath: String
    let itemName: String
}

private struct TransferBrowserItem: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64?
    
    var id: String { path }
}

private enum TransferEndpointKind: String, CaseIterable, Identifiable {
    case local
    case ssh
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .local: return "Local"
        case .ssh: return "SSH Host"
        }
    }
}

@MainActor
@Observable
private final class TransferPaneState {
    let id = UUID()
    let title: String
    var endpointKind: TransferEndpointKind = .local
    var selectedProfileID: UUID?
    var localPath: String
    var remotePath = "~"
    var items: [TransferBrowserItem] = []
    var isLoading = false
    var errorMessage = ""
    var isDropTargeted = false
    
    fileprivate var connectedProfileID: UUID?
    fileprivate var connection: SSHConnection?
    fileprivate var sftp: SSHSFTP?
    
    init(title: String) {
        self.title = title
        self.localPath = FileManager.default.homeDirectoryForCurrentUser.path
    }
    
    var displayedPath: String {
        endpointKind == .local ? localPath : remotePath
    }
    
    func resetForModeChange() {
        items = []
        errorMessage = ""
        if endpointKind == .local {
            disconnectRemote()
        }
    }
    
    func disconnectRemote() {
        sftp?.disconnect()
        connection?.disconnect()
        sftp = nil
        connection = nil
        connectedProfileID = nil
        remotePath = "~"
    }
}

struct TransferWorkspaceView: View {
    let profileStore: ConnectionProfileStore
    let connectProfile: (ConnectionProfile) async throws -> SSHConnection
    let onCreateHost: () -> Void
    
    @State private var leftPane = TransferPaneState(title: "Source")
    @State private var rightPane = TransferPaneState(title: "Destination")
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            
            HStack(spacing: 18) {
                TransferPaneView(
                    pane: leftPane,
                    profiles: profileStore.profiles,
                    onCreateHost: onCreateHost,
                    onRefresh: { Task { await refreshPane(leftPane) } },
                    onNavigateUp: { navigateUp(leftPane) },
                    onOpenItem: { item in open(item, in: leftPane) },
                    onDropProviders: { providers in handleDrop(providers: providers, into: leftPane) }
                )
                
                TransferPaneView(
                    pane: rightPane,
                    profiles: profileStore.profiles,
                    onCreateHost: onCreateHost,
                    onRefresh: { Task { await refreshPane(rightPane) } },
                    onNavigateUp: { navigateUp(rightPane) },
                    onOpenItem: { item in open(item, in: rightPane) },
                    onDropProviders: { providers in handleDrop(providers: providers, into: rightPane) }
                )
            }
        }
        .padding(28)
        .background(background)
        .task {
            await refreshPane(leftPane)
            await refreshPane(rightPane)
        }
        .onChange(of: leftPane.endpointKind) {
            leftPane.resetForModeChange()
            Task { await refreshPane(leftPane) }
        }
        .onChange(of: rightPane.endpointKind) {
            rightPane.resetForModeChange()
            Task { await refreshPane(rightPane) }
        }
        .onChange(of: leftPane.selectedProfileID) {
            leftPane.disconnectRemote()
            Task { await refreshPane(leftPane) }
        }
        .onChange(of: rightPane.selectedProfileID) {
            rightPane.disconnectRemote()
            Task { await refreshPane(rightPane) }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transfers")
                .font(.system(size: 30, weight: .semibold))
            
            Text("Drag files between local folders and SSH hosts. You can stage local -> SSH, SSH -> local, or SSH -> SSH transfers from one workspace.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 10) {
                Label("Drag files onto the opposite pane to transfer them.", systemImage: "arrow.left.and.right")
                Label("Folders can be browsed, but only files are transferable in this version.", systemImage: "folder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
    
    private var background: some View {
        LinearGradient(
            colors: [
                Color(NSColor.windowBackgroundColor),
                Color.cyan.opacity(0.03),
                Color(NSColor.textBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private func profile(for id: UUID?) -> ConnectionProfile? {
        guard let id else { return nil }
        return profileStore.profiles.first { $0.id == id }
    }
    
    private func refreshPane(_ pane: TransferPaneState) async {
        pane.isLoading = true
        pane.errorMessage = ""
        
        do {
            switch pane.endpointKind {
            case .local:
                pane.items = try loadLocalItems(at: pane.localPath)
            case .ssh:
                guard let profile = profile(for: pane.selectedProfileID) else {
                    pane.items = []
                    pane.errorMessage = profileStore.profiles.isEmpty ? "Create a host profile to browse SSH files." : "Select a host profile to browse."
                    pane.isLoading = false
                    return
                }
                let sftp = try await ensureRemoteReady(for: pane, profile: profile)
                _ = sftp
                pane.items = try await loadRemoteItems(for: pane)
            }
        } catch {
            pane.errorMessage = error.localizedDescription
        }
        
        pane.isLoading = false
    }
    
    private func ensureRemoteReady(for pane: TransferPaneState, profile: ConnectionProfile) async throws -> SSHSFTP {
        if pane.connectedProfileID != profile.id || pane.connection == nil || pane.sftp == nil {
            pane.disconnectRemote()
            let connection = try await connectProfile(profile)
            let sftp = try SSHSFTP(connection: connection)
            pane.connection = connection
            pane.sftp = sftp
            pane.connectedProfileID = profile.id
            pane.remotePath = try await resolveRemoteHome(for: connection)
        }
        
        guard let sftp = pane.sftp else {
            throw SSHError.sftpFailed("Unable to initialize SFTP session")
        }
        return sftp
    }
    
    private func resolveRemoteHome(for connection: SSHConnection) async throws -> String {
        connection.pauseChannel()
        defer { connection.resumeChannel() }
        try? await Task.sleep(for: .milliseconds(50))
        let output = try connection.execute("echo $HOME")
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "/" : trimmed
    }
    
    private func loadLocalItems(at path: String) throws -> [TransferBrowserItem] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let values: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: values, options: [.skipsHiddenFiles])
        
        return try urls.map { itemURL in
            let resourceValues = try itemURL.resourceValues(forKeys: Set(values))
            return TransferBrowserItem(
                name: itemURL.lastPathComponent,
                path: itemURL.path,
                isDirectory: resourceValues.isDirectory ?? false,
                size: resourceValues.fileSize.map(UInt64.init)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    private func loadRemoteItems(for pane: TransferPaneState) async throws -> [TransferBrowserItem] {
        guard let connection = pane.connection else {
            throw SSHError.connectionFailed("SSH connection is not available")
        }
        
        let escapedPath = pane.remotePath.replacingOccurrences(of: "'", with: "'\\''")
        connection.pauseChannel()
        defer { connection.resumeChannel() }
        try? await Task.sleep(for: .milliseconds(50))
        let output = try connection.execute("bash --noprofile --norc -c \"ls -1FA '\(escapedPath)' 2>/dev/null || ls -1F '\(escapedPath)'\"")
        let lines = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        
        return lines.compactMap { line in
            var name = line
            var isDirectory = false
            
            if name.hasSuffix("/") {
                name.removeLast()
                isDirectory = true
            } else if let last = name.last, "*@|=".contains(last) {
                name.removeLast()
            }
            
            guard name != ".", name != ".." else { return nil }
            let path = pane.remotePath == "/" ? "/\(name)" : "\(pane.remotePath)/\(name)"
            return TransferBrowserItem(name: name, path: path, isDirectory: isDirectory, size: nil)
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    
    private func open(_ item: TransferBrowserItem, in pane: TransferPaneState) {
        guard item.isDirectory else { return }
        switch pane.endpointKind {
        case .local:
            pane.localPath = item.path
        case .ssh:
            pane.remotePath = item.path
        }
        Task { await refreshPane(pane) }
    }
    
    private func navigateUp(_ pane: TransferPaneState) {
        switch pane.endpointKind {
        case .local:
            let parent = URL(fileURLWithPath: pane.localPath).deletingLastPathComponent().path
            if !parent.isEmpty {
                pane.localPath = parent
            }
        case .ssh:
            guard pane.remotePath != "/" else { return }
            let parts = pane.remotePath.split(separator: "/")
            pane.remotePath = parts.dropLast().isEmpty ? "/" : "/" + parts.dropLast().joined(separator: "/")
        }
        Task { await refreshPane(pane) }
    }
    
    private func handleDrop(providers: [NSItemProvider], into targetPane: TransferPaneState) -> Bool {
        if let jsonProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.json.identifier) }) {
            jsonProvider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
                guard let data, let payload = try? JSONDecoder().decode(TransferDragPayload.self, from: data) else { return }
                Task { await transfer(payload: payload, to: targetPane) }
            }
            return true
        }
        
        if let fileProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            fileProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { await transferExternalFile(url, to: targetPane) }
            }
            return true
        }
        
        return false
    }
    
    private func transfer(payload: TransferDragPayload, to targetPane: TransferPaneState) async {
        guard let sourcePane = sourcePane(for: payload.sourcePaneID), sourcePane.id != targetPane.id else { return }
        await transferFile(named: payload.itemName, sourcePath: payload.itemPath, from: sourcePane, to: targetPane)
    }
    
    private func transferExternalFile(_ fileURL: URL, to targetPane: TransferPaneState) async {
        await transferFile(named: fileURL.lastPathComponent, sourcePath: fileURL.path, from: nil, to: targetPane)
    }
    
    private func transferFile(named fileName: String, sourcePath: String, from sourcePane: TransferPaneState?, to targetPane: TransferPaneState) async {
        targetPane.isLoading = true
        targetPane.errorMessage = ""
        sourcePane?.errorMessage = ""
        
        do {
            switch (sourcePane?.endpointKind ?? .local, targetPane.endpointKind) {
            case (.local, .local):
                let destination = URL(fileURLWithPath: targetPane.localPath).appendingPathComponent(fileName).path
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destination)
            case (.local, .ssh):
                guard let profile = profile(for: targetPane.selectedProfileID) else {
                    throw SSHError.connectionFailed("Select a destination SSH host")
                }
                let sftp = try await ensureRemoteReady(for: targetPane, profile: profile)
                try sftp.upload(localPath: sourcePath, remotePath: remoteDestinationPath(in: targetPane, fileName: fileName))
            case (.ssh, .local):
                guard let sourcePane, let sftp = sourcePane.sftp else {
                    throw SSHError.sftpFailed("Source SFTP session is not available")
                }
                let destination = URL(fileURLWithPath: targetPane.localPath).appendingPathComponent(fileName).path
                try sftp.download(remotePath: sourcePath, localPath: destination)
            case (.ssh, .ssh):
                guard let sourcePane, let sourceSFTP = sourcePane.sftp else {
                    throw SSHError.sftpFailed("Source SFTP session is not available")
                }
                guard let profile = profile(for: targetPane.selectedProfileID) else {
                    throw SSHError.connectionFailed("Select a destination SSH host")
                }
                let targetSFTP = try await ensureRemoteReady(for: targetPane, profile: profile)
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + "-" + fileName)
                try sourceSFTP.download(remotePath: sourcePath, localPath: tempURL.path)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                try targetSFTP.upload(localPath: tempURL.path, remotePath: remoteDestinationPath(in: targetPane, fileName: fileName))
            }
            
            await refreshPane(targetPane)
            if let sourcePane {
                await refreshPane(sourcePane)
            }
        } catch {
            targetPane.errorMessage = "Transfer failed: \(error.localizedDescription)"
        }
        
        targetPane.isLoading = false
    }
    
    private func remoteDestinationPath(in pane: TransferPaneState, fileName: String) -> String {
        pane.remotePath == "/" ? "/\(fileName)" : "\(pane.remotePath)/\(fileName)"
    }
    
    private func sourcePane(for id: UUID) -> TransferPaneState? {
        if leftPane.id == id { return leftPane }
        if rightPane.id == id { return rightPane }
        return nil
    }
}

private struct TransferPaneView: View {
    @Bindable var pane: TransferPaneState
    let profiles: [ConnectionProfile]
    let onCreateHost: () -> Void
    let onRefresh: () -> Void
    let onNavigateUp: () -> Void
    let onOpenItem: (TransferBrowserItem) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(pane.isDropTargeted ? Color.accentColor.opacity(0.10) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(pane.isDropTargeted ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: pane.isDropTargeted ? 2 : 1)
        )
        .onDrop(of: [UTType.json.identifier, UTType.fileURL.identifier], isTargeted: $pane.isDropTargeted) { providers in
            onDropProviders(providers)
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pane.title)
                    .font(.headline)
                Spacer()
                Picker("Endpoint", selection: $pane.endpointKind) {
                    ForEach(TransferEndpointKind.allCases) { endpoint in
                        Text(endpoint.title).tag(endpoint)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            
            if pane.endpointKind == .ssh {
                HStack {
                    if profiles.isEmpty {
                        Button("Create SSH Host", action: onCreateHost)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Picker("SSH Host", selection: $pane.selectedProfileID) {
                            Text("Select Host").tag(Optional<UUID>.none)
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        .frame(maxWidth: 260)
                    }
                    Spacer()
                }
            }
            
            HStack(spacing: 10) {
                Button(action: onNavigateUp) {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canNavigateUp)
                
                Text(pane.displayedPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                
                Spacer()
                
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if pane.isLoading {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !pane.errorMessage.isEmpty && pane.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(pane.errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Refresh", action: onRefresh)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(pane.items) { item in
                TransferItemRow(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        onOpenItem(item)
                    }
                    .onDrag {
                        guard !item.isDirectory else { return NSItemProvider() }
                        let payload = TransferDragPayload(sourcePaneID: pane.id, itemPath: item.path, itemName: item.name)
                        let provider = NSItemProvider()
                        if let data = try? JSONEncoder().encode(payload) {
                            provider.registerDataRepresentation(forTypeIdentifier: UTType.json.identifier, visibility: .all) { completion in
                                completion(data, nil)
                                return nil
                            }
                        }
                        return provider
                    }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            
            if !pane.errorMessage.isEmpty {
                Text(pane.errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
    
    private var canNavigateUp: Bool {
        switch pane.endpointKind {
        case .local:
            return pane.localPath != "/"
        case .ssh:
            return pane.remotePath != "/"
        }
    }
}

private struct TransferItemRow: View {
    let item: TransferBrowserItem
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(for: item.name))
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                Text(item.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let size = item.size, !item.isDirectory {
                Text(formatFileSize(size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }
    
    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "zip", "tar", "gz", "rar", "7z": return "doc.zipper"
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "json", "yml", "yaml", "toml", "xml": return "doc.badge.gearshape"
        case "sh", "zsh", "bash": return "terminal"
        case "md", "txt", "log": return "doc.plaintext"
        default: return "doc"
        }
    }
    
    private func formatFileSize(_ size: UInt64) -> String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(size) / (1024 * 1024 * 1024))
    }
}
