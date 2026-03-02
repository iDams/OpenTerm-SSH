import SwiftUI
import UniformTypeIdentifiers

struct SFTPView: View {
    let connection: SSHConnection
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
        VStack(spacing: 0) {
            pathBar
            
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let sftp = sftp, sftp.isConnected {
                fileList
            } else {
                disconnectedView
            }
        }
        .onAppear {
            if sftp == nil {
                initSFTP()
            }
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
    
    // MARK: - Path bar with inline action buttons
    private var pathBar: some View {
        HStack(spacing: 8) {
            Button {
                navigateToParent()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(currentPath == "/" || isLoading)
            
            Text(currentPath)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.head)
            
            Spacer()
            
            // Inline action buttons (only visible inside SFTP)
            Button {
                refreshList()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(sftp == nil || isLoading)
            
            Button {
                showUploadPicker = true
            } label: {
                Image(systemName: "arrow.up.circle")
            }
            .buttonStyle(.borderless)
            .disabled(sftp == nil || isLoading)
            
            Button {
                showCreateFolder = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(sftp == nil || isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - File list
    private var fileList: some View {
        List {
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
            
            ForEach(files, id: \.name) { file in
                HStack {
                    Image(systemName: file.isDirectory ? "folder.fill" : iconForFile(file.name))
                        .foregroundStyle(file.isDirectory ? .blue : .gray)
                    
                    Text(file.name)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if !file.isDirectory && file.size > 0 {
                        Text(formatFileSize(file.size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
        }
        .listStyle(.inset)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - SFTP Operations
    
    private func initSFTP() {
        isLoading = true
        errorMessage = ""
        
        Task.detached {
            do {
                let newSFTP = try SSHSFTP(connection: connection)
                
                // Resolve the user's home directory
                var resolvedHome = "/"
                do {
                    connection.pauseChannel()
                    Thread.sleep(forTimeInterval: 0.05)
                    let output = try connection.execute("echo $HOME")
                    connection.resumeChannel()
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        resolvedHome = trimmed
                    }
                } catch {
                    connection.resumeChannel()
                    // Fallback to root if we can't determine home
                }
                
                let homePath = resolvedHome
                await MainActor.run {
                    self.sftp = newSFTP
                    self.currentPath = homePath
                    self.isLoading = false
                }
                await listDirectory()
            } catch {
                await MainActor.run {
                    self.errorMessage = "Error starting SFTP: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func listDirectory() async {
        guard sftp != nil else { return }
        
        await MainActor.run {
            isLoading = true
            errorMessage = ""
        }
        
        do {
            // Use shell command to get files WITH directory markers
            let escapedPath = currentPath.replacingOccurrences(of: "'", with: "'\\''")
            
            connection.pauseChannel()
            Thread.sleep(forTimeInterval: 0.05)
            // Execute in a clean bash shell to prevent .bashrc / MOTD texts from corrupting the file list output
            let output = try connection.execute("bash --noprofile --norc -c \"ls -1FA '\(escapedPath)' 2>/dev/null || ls -1F '\(escapedPath)'\"")
            connection.resumeChannel()
            
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
}