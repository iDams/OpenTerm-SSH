import SwiftUI
import UniformTypeIdentifiers

struct SFTPView: View {
    let profile: ConnectionProfile
    let connectProfile: (ConnectionProfile) async throws -> SSHConnection
    
    @State private var browserConnection: SSHConnection?
    @State private var sftp: SSHSFTP?
    @State private var currentPath = "~"
    @State private var files: [SSHFileInfo] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showCreateFolder = false
    @State private var showRename = false
    @State private var showUploadPicker = false
    @State private var newFolderName = ""
    @State private var selectedItem: SSHFileInfo?
    @State private var newName = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            browserCard
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(background)
    }
    
    private var browserCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            pathBar
            
            if isLoading {
                loadingView
            } else if let sftp = sftp, sftp.isConnected {
                fileList
            } else {
                disconnectedView
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onAppear {
            if sftp == nil && !isLoading {
                initSFTP()
            }
        }
        .onDisappear {
            disconnectSFTP()
        }
        .alert("New folder", isPresented: $showCreateFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                createFolder()
            }
            .disabled(newFolderName.isEmpty)
        }
        .alert("Rename", isPresented: $showRename) {
            TextField("New name", text: $newName)
            Button("Cancel", role: .cancel) {
                newName = ""
                selectedItem = nil
            }
            Button("Rename") {
                renameItem()
            }
            .disabled(newName.isEmpty)
        }
        .fileImporter(isPresented: $showUploadPicker, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                uploadFile(from: url)
            case .failure:
                errorMessage = "Error selecting file"
            }
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
    
    // MARK: - Path bar with inline action buttons
    private var pathBar: some View {
        HStack(spacing: 10) {
            Button {
                navigateToParent()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .disabled(currentPath == "/" || isLoading)
            
            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                
                Text(currentPath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .textSelection(.enabled)
                
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            Spacer()
            
            Button {
                refreshList()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .disabled(sftp == nil || isLoading)
            
            Button {
                showUploadPicker = true
            } label: {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .disabled(sftp == nil || isLoading)
            
            Button {
                showCreateFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderless)
            .disabled(sftp == nil || isLoading)
        }
    }
    
    // MARK: - File list
    private var fileList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(files, id: \.name) { file in
                        fileRow(file)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
    
    private func fileRow(_ file: SSHFileInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.isDirectory ? "folder.fill" : iconForFile(file.name))
                .foregroundStyle(file.isDirectory ? .blue : .secondary)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(file.isDirectory ? remoteChildPath(for: file.name) : fileKindLabel(for: file.name))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if !file.isDirectory && file.size > 0 {
                Text(formatFileSize(file.size))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if file.isDirectory {
                navigateTo(file.name)
            }
        }
        .contextMenu {
            if !file.isDirectory {
                Button {
                    downloadFile(file)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            
            Button {
                selectedItem = file
                newName = file.name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            
            Divider()
            
            Button(role: .destructive) {
                deleteItem(file)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("SFTP not connected")
                .font(.headline)
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            
            Button("Connect SFTP") {
                initSFTP()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
    
    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading remote contents…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
    
    // MARK: - SFTP Operations
    
    private func initSFTP() {
        isLoading = true
        errorMessage = ""
        
        Task.detached {
            do {
                let dedicatedConnection = try await connectProfile(profile)
                let newSFTP = try SSHSFTP(connection: dedicatedConnection)
                
                // Resolve the user's home directory
                var resolvedHome = "/"
                do {
                    dedicatedConnection.pauseChannel()
                    Thread.sleep(forTimeInterval: 0.05)
                    let output = try dedicatedConnection.execute("echo $HOME")
                    dedicatedConnection.resumeChannel()
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        resolvedHome = trimmed
                    }
                } catch {
                    dedicatedConnection.resumeChannel()
                    // Fallback to root if we can't determine home
                }
                
                let homePath = resolvedHome
                await MainActor.run {
                    self.browserConnection = dedicatedConnection
                    self.sftp = newSFTP
                    self.currentPath = homePath
                    self.isLoading = false
                }
                await listDirectory()
            } catch {
                await MainActor.run {
                    self.disconnectSFTP()
                    self.errorMessage = "Error starting SFTP: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func listDirectory() async {
        guard sftp != nil, let browserConnection else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            // Use shell command to get files WITH directory markers
            let escapedPath = currentPath.replacingOccurrences(of: "'", with: "'\\''")
            
            browserConnection.pauseChannel()
            Thread.sleep(forTimeInterval: 0.05)
            // Execute in a clean bash shell to prevent .bashrc / MOTD texts from corrupting the file list output
            let output = try browserConnection.execute("bash --noprofile --norc -c \"ls -1FA '\(escapedPath)' 2>/dev/null || ls -1F '\(escapedPath)'\"")
            browserConnection.resumeChannel()
            
            // Filter out any stray empty lines or trailing newlines
            let lines = output.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            
            var fileList: [SSHFileInfo] = []
            for line in lines {
                var name = String(line)
                var isDir = false
                
                // ls -F appends indicators: / for dir, * for executable, @ for symlink, | for pipe, = for socket
                if name.hasSuffix("/") {
                    name = String(name.dropLast())
                    isDir = true
                } else if name.hasSuffix("*") || name.hasSuffix("@") || name.hasSuffix("|") || name.hasSuffix("=") {
                    name = String(name.dropLast())
                }
                
                // Skip . and .. just in case
                if name == "." || name == ".." { continue }
                
                fileList.append(SSHFileInfo(name: name, size: 0, isDirectory: isDir))
            }
            
            await MainActor.run {
                self.files = fileList.sorted { a, b in
                    if a.isDirectory != b.isDirectory {
                        return a.isDirectory
                    }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error listing directory: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    private func refreshList() {
        Task {
            await listDirectory()
        }
    }
    
    private func navigateTo(_ name: String) {
        if currentPath == "/" {
            currentPath = "/\(name)"
        } else {
            currentPath = "\(currentPath)/\(name)"
        }
        refreshList()
    }
    
    private func navigateToParent() {
        if currentPath == "/" { return }
        let components = currentPath.split(separator: "/")
        if components.isEmpty {
            currentPath = "/"
        } else {
            currentPath = "/" + components.dropLast().joined(separator: "/")
            if currentPath.isEmpty { currentPath = "/" }
        }
        refreshList()
    }
    
    private func createFolder() {
        guard let sftp = sftp, !newFolderName.isEmpty else { return }
        
        let folderPath = currentPath == "/" ? "/\(newFolderName)" : "\(currentPath)/\(newFolderName)"
        
        Task.detached {
            do {
                try sftp.createDirectory(folderPath)
                await MainActor.run {
                    self.newFolderName = ""
                }
                await listDirectory()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error creating folder: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func renameItem() {
        guard let sftp = sftp, let item = selectedItem, !newName.isEmpty else { return }
        
        let oldPath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
        let newPath = currentPath == "/" ? "/\(newName)" : "\(currentPath)/\(newName)"
        
        Task.detached {
            do {
                try sftp.rename(oldPath: oldPath, newPath: newPath)
                await MainActor.run {
                    self.newName = ""
                    self.selectedItem = nil
                }
                await listDirectory()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error renaming: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteItem(_ item: SSHFileInfo) {
        guard let sftp = sftp else { return }
        
        let path = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
        
        Task.detached {
            do {
                try sftp.remove(path)
                await listDirectory()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error deleting: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func uploadFile(from url: URL) {
        guard let sftp = sftp else { return }
        
        let fileName = url.lastPathComponent
        let remotePath = currentPath == "/" ? "/\(fileName)" : "\(currentPath)/\(fileName)"
        
        Task.detached {
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                
                try sftp.upload(localPath: url.path, remotePath: remotePath)
                await listDirectory()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error uploading file: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func downloadFile(_ item: SSHFileInfo) {
        guard let sftp = sftp else { return }
        
        let remotePath = currentPath == "/" ? "/\(item.name)" : "\(currentPath)/\(item.name)"
        
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = item.name
        savePanel.canCreateDirectories = true
        
        savePanel.begin { response in
            guard response == .OK, let localURL = savePanel.url else { return }
            
            Task.detached {
                do {
                    try sftp.download(remotePath: remotePath, localPath: localURL.path)
                    await MainActor.run {
                        self.errorMessage = "File downloaded successfully"
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = "Error downloading: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "py": return "doc.text"
        case "js", "ts": return "doc.text"
        case "sh", "bash", "zsh": return "terminal"
        case "json", "yml", "yaml", "xml", "toml": return "doc.badge.gearshape"
        case "md", "txt", "log": return "doc.plaintext"
        case "jpg", "jpeg", "png", "gif", "svg", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "flac", "ogg": return "music.note"
        case "zip", "tar", "gz", "bz2", "7z", "rar": return "doc.zipper"
        default: return "doc.fill"
        }
    }
    
    private func formatFileSize(_ size: UInt64) -> String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
        return String(format: "%.1f GB", Double(size) / (1024 * 1024 * 1024))
    }
    
    private func remoteChildPath(for name: String) -> String {
        currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
    }
    
    private func fileKindLabel(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext.isEmpty {
            return remoteChildPath(for: name)
        }
        return ext.uppercased() + " file"
    }
    
    @MainActor
    private func disconnectSFTP() {
        sftp?.disconnect()
        browserConnection?.disconnect()
        sftp = nil
        browserConnection = nil
    }
}
