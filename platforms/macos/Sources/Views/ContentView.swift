import SwiftUI
import Observation

enum NavigationItem: String, CaseIterable, Identifiable {
    case hosts = "Hosts"
    case transfers = "SFTP"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .hosts: return "server.rack"
        case .transfers: return "arrow.left.arrow.right.square"
        }
    }
}

struct ContentView: View {
    @State private var profileStore = ConnectionProfileStore()
    @State private var searchText = ""
    @State private var selectedNavItem: NavigationItem? = .hosts
    @State private var showNewHostSheet = false
    
    // Connection & Terminal States
    enum TabType: Hashable {
        case home
        case local(UUID)
        case connecting(ConnectionProfile, UUID)
        case ssh(SSHConnection, UUID)
        
        var id: UUID {
            switch self {
            case .home: return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            case .local(let id): return id
            case .connecting(_, let id): return id
            case .ssh(_, let id): return id
            }
        }
        
        var title: String {
            switch self {
            case .home: return "Hosts"
            case .local: return "Terminal"
            case .connecting(let profile, _): return profile.name
            case .ssh(let conn, _): return "\(conn.username)@\(conn.host)"
            }
        }
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .local: return "terminal"
            case .connecting: return "wifi"
            case .ssh: return "network"
            }
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(self.id)
        }
        
        static func == (lhs: TabType, rhs: TabType) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    @State private var tabs: [TabType] = [.home]
    @State private var activeTabId: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    @State private var connectingProfiles: Set<UUID> = []
    @State private var connectionTasks: [UUID: Task<Void, Never>] = [:]
    @State private var sshTerminalSessions: [UUID: TerminalSession] = [:]
    @State private var sshProfilesByTab: [UUID: ConnectionProfile] = [:]
    @State private var sshViewModeByTab: [UUID: Int] = [:]
    @State private var sshTerminalMountVersionByTab: [UUID: Int] = [:]
    @State private var errorMessage = ""
    
    // Host Key Verification States
    @State private var showHostKeyAlert = false
    @State private var pendingHostKeyInfo: SSHHostKeyInfo?
    @State private var hostKeyAlertContinuation: CheckedContinuation<SSHHostKeyDecision, Never>?
    
    // Profile Editing / Creation States
    @State private var editingProfile: ConnectionProfile?
    
    @State private var profileName = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var privateKeyPath = defaultPrivateKeyPath() ?? ""
    @State private var authMethod = 0
    @State private var password = ""
    @State private var savePasswordInKeychain = false
    @State private var showComingSoon = false
    @State private var viewLayout = HostsViewLayoutType.grid
    @State private var selectedProfileID: ConnectionProfile.ID?
    @State private var hoveredLayout: HostsViewLayoutType?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNavItem) {
                Section("Workspace") {
                    Label(NavigationItem.hosts.rawValue, systemImage: NavigationItem.hosts.icon)
                        .tag(NavigationItem.hosts)
                }
                
                Section("Transfer") {
                    Label(NavigationItem.transfers.rawValue, systemImage: NavigationItem.transfers.icon)
                        .tag(NavigationItem.transfers)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Group {
                if selectedNavItem == .transfers {
                    homeWorkspaceView
                } else {
                    VStack(spacing: 0) {
                        // Chrome-style Tab Bar
                        HStack(spacing: 0) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 0) {
                                    ForEach(tabs, id: \.id) { tab in
                                        chromeTab(for: tab)
                                    }
                                }
                                .padding(.top, 6)
                                .padding(.horizontal, 4)
                            }
                            Spacer()
                        }
                        .frame(height: 38)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
                        
                        ZStack {
                            Color(NSColor.textBackgroundColor).ignoresSafeArea()
                            activeSessionLayer
                            
                            if shouldShowWorkspaceView {
                                homeWorkspaceView
                                    .zIndex(10)
                            }
                        }
                    }
                }
            }
        }
        .alert("Coming Soon", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This feature is not yet available, but will be implemented soon.")
        }
        .alert("Verify Host Key", isPresented: $showHostKeyAlert) {
            Button("Reject", role: .cancel) {
                hostKeyAlertContinuation?.resume(returning: .reject)
                hostKeyAlertContinuation = nil
            }
            Button("Trust once") {
                hostKeyAlertContinuation?.resume(returning: .acceptOnce)
                hostKeyAlertContinuation = nil
            }
            Button("Trust and save") {
                hostKeyAlertContinuation?.resume(returning: .acceptAndSave)
                hostKeyAlertContinuation = nil
            }
        } message: {
            if let info = pendingHostKeyInfo {
                Text("""
                The server \(info.host):\(info.port) is not in your list of known hosts.
                
                Key type: \(keyTypeName(info.keyType))
                SHA256 Fingerprint: \(info.fingerprintSHA256 ?? "Not available")
                
                Do you want to trust this server?
                """)
            } else {
                Text("Host key information not available")
            }
        }
        .sheet(item: $editingProfile) { profile in
            EditProfileView(profile: profile) { updatedProfile, newPassword in
                Task {
                    await profileStore.saveProfile(updatedProfile, password: newPassword)
                    editingProfile = nil
                }
            }
        }
        .sheet(isPresented: $showNewHostSheet) {
            newHostSheet
        }
        .modifier(HostsSearchModifier(isActive: isShowingHostsHome, searchText: $searchText))
        .onChange(of: activeTabId) {
            refreshTerminalMountIfNeeded(for: activeTabId)
        }
        .toolbar {
            if isShowingHostsHome {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: { showNewHostSheet = true }) {
                        Label("New Host", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    
                    Button(action: openLocalTerminal) {
                        Label("Terminal", systemImage: "terminal")
                    }
                    
                    Button(action: { showComingSoon = true }) {
                        Label("Serial", systemImage: "cable.connector")
                    }
                }
                
                ToolbarItemGroup(placement: .primaryAction) {
                    HStack(spacing: 2) {
                        toolbarLayoutButton(for: .grid)
                        toolbarLayoutButton(for: .list)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.92), in: Capsule())
                }
            }
        }
    }
    
    // MARK: - Chrome-Style Tab
    @ViewBuilder
    private func chromeTab(for type: TabType) -> some View {
        let isActive = activeTabId == type.id
        
        HStack(spacing: 4) {
            // Tab icon
            Image(systemName: type.icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)
            
            Text(type.title)
                .font(.system(size: 12, weight: isActive ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(isActive ? .primary : .secondary)
            
            if type != .home {
                Button(action: {
                    closeTab(id: type.id)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color(NSColor.separatorColor).opacity(0.001))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 0.8 : 0.0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
            .fill(isActive
                  ? Color(NSColor.textBackgroundColor)
                  : Color(NSColor.windowBackgroundColor).opacity(0.01))
        )
        .overlay(
            // Subtle top border for active tab
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 8
            )
            .strokeBorder(
                isActive ? Color(NSColor.separatorColor).opacity(0.5) : Color.clear,
                lineWidth: 0.5
            )
        )
        .onTapGesture {
            activeTabId = type.id
        }
        .onHover { hovering in
            // Future: could track hover per-tab for close button reveal
        }
    }
    
    @ViewBuilder
    private func toolbarLayoutButton(for layout: HostsViewLayoutType) -> some View {
        Button {
            viewLayout = layout
        } label: {
            Image(systemName: layout.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(buttonHighlight(for: layout), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(layout.title)
        .onHover { isHovering in
            hoveredLayout = isHovering ? layout : (hoveredLayout == layout ? nil : hoveredLayout)
        }
    }
    
    private var toolbarButtonFill: Color {
        Color.primary.opacity(0.09)
    }
    
    private func buttonHighlight(for layout: HostsViewLayoutType) -> Color {
        if viewLayout == layout || hoveredLayout == layout {
            return toolbarButtonFill
        }
        return .clear
    }
    
    private var homeWorkspaceView: some View {
        Group {
            switch selectedNavItem ?? .hosts {
            case .hosts:
                HostsHomeView(
                    profileStore: profileStore,
                    searchText: $searchText,
                    viewLayout: $viewLayout,
                    selectedProfileID: $selectedProfileID,
                    connectingProfiles: connectingProfiles,
                    onCreateHost: { showNewHostSheet = true },
                    onOpenLocalTerminal: openLocalTerminal,
                    onConnect: { profile in
                        guard !connectingProfiles.contains(profile.id) else { return }
                        Task { await applyProfileAndConnect(profile) }
                    },
                    onEdit: { profile in
                        editingProfile = profile
                    },
                    onDuplicate: { profile in
                        Task { await profileStore.duplicateProfile(profile) }
                    },
                    onDelete: { profile in
                        Task { await profileStore.deleteProfile(profile) }
                    }
                )
            case .transfers:
                TransferWorkspaceView(
                    profileStore: profileStore,
                    connectProfile: { profile in
                        try await openSSHConnection(for: profile)
                    },
                    onCreateHost: { showNewHostSheet = true }
                )
            }
        }
    }
    
    @ViewBuilder
    private var activeSessionLayer: some View {
        if let tab = tabs.first(where: { $0.id == activeTabId }) {
            switch tab {
            case .home:
                Color.clear
            case .local:
                LocalTerminalContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            case .connecting(let profile, let id):
                ConnectingTerminalView(profile: profile, errorMessage: errorMessage) {
                    cancelConnection(tabId: id)
                }
            case .ssh(let conn, _):
                connectedDetailView(conn: conn, tabId: tab.id)
            }
        }
    }
    
    private var isShowingHostsHome: Bool {
        activeTabId == TabType.home.id && selectedNavItem == .hosts
    }
    
    private var shouldShowWorkspaceView: Bool {
        selectedNavItem == .transfers || activeTabId == TabType.home.id || !tabs.contains(where: { $0.id == activeTabId })
    }

    private func openLocalTerminal() {
        let newLocalId = UUID()
        let localTab = TabType.local(newLocalId)
        tabs.append(localTab)
        activeTabId = newLocalId
    }
    
    // MARK: - New Host Sheet
    
    private var parsedPort: UInt16? {
        UInt16(port)
    }
    
    private var newHostSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Host").font(.headline)
                    Text("Configure SSH connection details").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Profile Name:")
                        .gridColumnAlignment(.trailing)
                    TextField("", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Host / IP Address:")
                    TextField("", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Port:")
                    TextField("", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                Divider()
                    .gridCellColumns(2)
                    .padding(.vertical, 4)
                
                GridRow {
                    Text("Username:")
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Authentication:")
                    Picker("", selection: $authMethod) {
                        Text("Password").tag(0)
                        Text("SSH Key").tag(1)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                }
                
                if authMethod == 0 {
                    GridRow {
                        Text("Password:")
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("", text: $password)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Save password in Keychain", isOn: $savePasswordInKeychain)
                                .controlSize(.small)
                        }
                    }
                } else {
                    GridRow {
                        Text("Private Key Path:")
                        HStack(spacing: 8) {
                            TextField("", text: $privateKeyPath)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.showsHiddenFiles = true
                                panel.title = "Select SSH Private Key"
                                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
                                if panel.runModal() == .OK, let url = panel.url {
                                    privateKeyPath = url.path
                                }
                            } label: {
                                Image(systemName: "folder")
                                    .frame(height: 18)
                            }
                            .help("Select private key file")
                        }
                    }
                }
            }
            .padding(20)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel") { showNewHostSheet = false }
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") { Task { await saveProfile() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(profileName.isEmpty || host.isEmpty || username.isEmpty)
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 480)
    }
    
    // MARK: - Connected State View
    
    @State private var showModeToggle = false
    
    @ViewBuilder
    private func connectedDetailView(conn: SSHConnection, tabId: UUID) -> some View {
        let selectedTab = sshViewModeByTab[tabId, default: 0]
        
        ZStack(alignment: .bottomTrailing) {
            // Terminal view
            terminalView(conn: conn, tabId: tabId)
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)
            
            // SFTP view - only mount when needed to avoid racing with terminal channel
            if selectedTab == 1, let profile = sshProfilesByTab[tabId] {
                SFTPView(
                    profile: profile,
                    connectProfile: { profile in
                        try await openSSHConnection(for: profile)
                    }
                )
                .id(tabId)
            }
            
            // Floating toggle capsule
            HStack(spacing: 2) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sshViewModeByTab[tabId] = 0
                    }
                }) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedTab == 0 ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(selectedTab == 0 ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sshViewModeByTab[tabId] = 1
                    }
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedTab == 1 ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(selectedTab == 1 ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .opacity(showModeToggle || selectedTab == 1 ? 1 : 0.15)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    showModeToggle = hovering
                }
            }
            .padding(.trailing, 28)
            .padding(.bottom, 28)
        }
    }
    
    @ViewBuilder
    private func terminalView(conn: SSHConnection, tabId: UUID) -> some View {
        VStack(spacing: 0) {
            if let session = sshTerminalSessions[tabId] {
                let mountVersion = sshTerminalMountVersionByTab[tabId, default: 0]
                PersistentTerminalSessionContainerView(
                    session: session,
                    isVisible: activeTabId == tabId && selectedNavItem == .hosts
                )
                    .id("\(tabId.uuidString)-\(mountVersion)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Preparing terminal…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
            
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    
    // MARK: - Actions
    
    private func cancelConnection(tabId: UUID) {
        connectionTasks[tabId]?.cancel()
        connectionTasks.removeValue(forKey: tabId)
        
        // Find which profile this tab belonged to
        if let tab = tabs.first(where: { $0.id == tabId }),
           case .connecting(let profile, _) = tab {
            connectingProfiles.remove(profile.id)
        }
        
        closeTab(id: tabId)
    }
    
    private func applyProfileAndConnect(_ profile: ConnectionProfile) async {
        guard !connectingProfiles.contains(profile.id) else { return }
        
        connectingProfiles.insert(profile.id)
        errorMessage = ""
        
        let newTabId = UUID()
        let connectingTab = TabType.connecting(profile, newTabId)
        
        // Spawn tab immediately
        tabs.append(connectingTab)
        activeTabId = newTabId
        
        // Retrieve saved password safely
        var passwordToUse = ""
        if profile.savePassword {
            if let savedPassword = await profileStore.getSavedPassword(for: profile) {
                passwordToUse = savedPassword
            }
        }
        
        let task = Task {
            await connectToSSH(profile: profile, tabId: newTabId, password: passwordToUse)
        }
        connectionTasks[newTabId] = task
    }
    
    private func saveProfile() async {
        guard let parsedPort else { return }

        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalPrivateKey = authMethod == 1 ? privateKeyPath : ""
        let finalSavePassword = authMethod == 0 ? savePasswordInKeychain : false
        
        let profile = ConnectionProfile(
            name: trimmedName,
            host: host,
            port: parsedPort,
            username: username,
            privateKeyPath: finalPrivateKey,
            savePassword: finalSavePassword
        )
        await profileStore.saveProfile(profile, password: finalSavePassword ? password : nil)
        
        // Reset and close
        profileName = ""
        host = ""
        username = ""
        password = ""
        authMethod = 0
        showNewHostSheet = false
    }
    
    private func openSSHConnection(for profile: ConnectionProfile) async throws -> SSHConnection {
        let normalizedHost = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrivateKeyPath = profile.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let conn = SSHConnection(host: normalizedHost, port: profile.port, username: normalizedUsername)
        
        var passwordToUse = ""
        if profile.savePassword, let savedPassword = await profileStore.getSavedPassword(for: profile) {
            passwordToUse = savedPassword
        }
        
        do {
            try await conn.connectAsync(
                password: passwordToUse.isEmpty ? nil : passwordToUse,
                privateKey: normalizedPrivateKeyPath.isEmpty ? nil : normalizedPrivateKeyPath,
                hostKeyCallback: { info -> SSHHostKeyDecision in
                    return await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            self.pendingHostKeyInfo = info
                            self.showHostKeyAlert = true
                            self.hostKeyAlertContinuation = continuation
                        }
                    }
                }
            )
            return conn
        } catch {
            conn.disconnect()
            throw error
        }
    }
    
    private func connectToSSH(profile: ConnectionProfile, tabId: UUID, password: String) async {
        let normalizedHost = profile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = profile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPrivateKeyPath = profile.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let conn = SSHConnection(host: normalizedHost, port: profile.port, username: normalizedUsername)
        
        do {
            try await conn.connectAsync(
                password: password.isEmpty ? nil : password,
                privateKey: normalizedPrivateKeyPath.isEmpty ? nil : normalizedPrivateKeyPath,
                hostKeyCallback: { info -> SSHHostKeyDecision in
                    return await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            self.pendingHostKeyInfo = info
                            self.showHostKeyAlert = true
                            self.hostKeyAlertContinuation = continuation
                        }
                    }
                }
            )
            
            // Detect remote OS internally before establishing the UI tab
            var detectedOS = profile.detectedOS
            if detectedOS == nil {
                do {
                    conn.pauseChannel()
                    let unameObj = try conn.execute("uname -s")
                    let osName = unameObj.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    
                    if osName.contains("darwin") {
                        detectedOS = "mac"
                    } else if osName.contains("linux") {
                        let releaseObj = try conn.execute("cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null")
                        let releaseStr = releaseObj.lowercased()
                        if releaseStr.contains("ubuntu") {
                            detectedOS = "ubuntu"
                        } else if releaseStr.contains("debian") {
                            detectedOS = "debian"
                        } else if releaseStr.contains("raspbian") {
                            detectedOS = "raspberrypi"
                        } else {
                            detectedOS = "linux"
                        }
                    } else {
                        detectedOS = osName
                    }
                    conn.resumeChannel()
                } catch {
                    conn.resumeChannel()
                    // Silently fail OS detection
                }
            }
            
            let finalProfile = profile
            
            let terminalSession = try await MainActor.run {
                try TerminalSession(connection: conn)
            }
            
            await MainActor.run {
                if Task.isCancelled {
                    terminalSession.stop()
                    conn.disconnect()
                    return
                }
                
                // Replace connecting tab with connected tab
                withAnimation {
                    if let index = tabs.firstIndex(where: { $0.id == tabId }) {
                        tabs[index] = .ssh(conn, tabId)
                    }
                }
                sshTerminalSessions[tabId] = terminalSession
                sshProfilesByTab[tabId] = finalProfile
                sshViewModeByTab[tabId] = 0
                sshTerminalMountVersionByTab[tabId] = 0
                connectingProfiles.remove(finalProfile.id)
                connectionTasks.removeValue(forKey: tabId)
                
                // Persist detected OS if updated
                if finalProfile.detectedOS != detectedOS {
                    var updatedProfile = finalProfile
                    updatedProfile.detectedOS = detectedOS
                    Task {
                        await profileStore.saveProfile(updatedProfile, password: password)
                    }
                    sshProfilesByTab[tabId] = updatedProfile
                }
            }
        } catch {
            await MainActor.run {
                if !Task.isCancelled {
                    errorMessage = "Error connecting to \(normalizedHost):\(profile.port) as \(normalizedUsername): \(error.localizedDescription)"
                    // Leave the tab open so user can see the error, or user can cancel it.
                } else {
                    connectingProfiles.remove(profile.id)
                    connectionTasks.removeValue(forKey: tabId)
                }
            }
        }
    }
    
    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        
        if case .ssh(let conn, _) = tabs[index] {
            sshTerminalSessions[id]?.stop()
            sshTerminalSessions.removeValue(forKey: id)
            sshProfilesByTab.removeValue(forKey: id)
            sshViewModeByTab.removeValue(forKey: id)
            sshTerminalMountVersionByTab.removeValue(forKey: id)
            conn.disconnect()
        }
        
        tabs.remove(at: index)
        
        if activeTabId == id {
            activeTabId = tabs.last?.id ?? TabType.home.id
        }
        
        if tabs.isEmpty {
            tabs.append(.home)
            activeTabId = TabType.home.id
        }
    }
    
    private func keyTypeName(_ type: SSHKeyType) -> String {
        switch type {
        case .rsa: return "RSA"
        case .ecdsa: return "ECDSA"
        case .ed25519: return "Ed25519"
        case .rsaCert: return "RSA (Certificate)"
        case .ecdsaCert: return "ECDSA (Certificate)"
        case .ed25519Cert: return "Ed25519 (Certificate)"
        case .unknown: return "Unknown"
        }
    }
    
    private func refreshTerminalMountIfNeeded(for tabId: UUID) {
        guard tabs.contains(where: {
            if case .ssh(_, let id) = $0 { return id == tabId }
            return false
        }) else { return }
        sshTerminalMountVersionByTab[tabId, default: 0] += 1
    }
}

private struct HostsSearchModifier: ViewModifier {
    let isActive: Bool
    @Binding var searchText: String
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $searchText, placement: .toolbar, prompt: "Search hosts")
        } else {
            content
        }
    }
}

// MARK: - Legacy Edit View Component

struct EditProfileView: View {
    let profile: ConnectionProfile
    let onSave: (ConnectionProfile, String?) -> Void
    
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var authMethod: Int
    @State private var privateKeyPath: String
    @State private var savePassword: Bool
    @State private var password: String = ""
    @Environment(\.dismiss) private var dismiss
    
    init(profile: ConnectionProfile, onSave: @escaping (ConnectionProfile, String?) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _host = State(initialValue: profile.host)
        _port = State(initialValue: "\(profile.port)")
        _username = State(initialValue: profile.username)
        // If it possessed a private key path previously, default to Key mode.
        _authMethod = State(initialValue: profile.privateKeyPath.isEmpty ? 0 : 1)
        _privateKeyPath = State(initialValue: profile.privateKeyPath)
        _savePassword = State(initialValue: profile.savePassword)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Image(systemName: "pencil")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.indigo.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Profile").font(.headline)
                    Text("Modify existing SSH connection").font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Profile Name:")
                        .gridColumnAlignment(.trailing)
                    TextField("", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Host / IP Address:")
                    TextField("", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Port:")
                    TextField("", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                
                Divider()
                    .gridCellColumns(2)
                    .padding(.vertical, 4)
                
                GridRow {
                    Text("Username:")
                    TextField("", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                GridRow {
                    Text("Authentication:")
                    Picker("", selection: $authMethod) {
                        Text("Password").tag(0)
                        Text("SSH Key").tag(1)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                }
                
                if authMethod == 0 {
                    GridRow {
                        Text("Password:")
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("New Password (blank to keep existing)", text: $password)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Save password in Keychain", isOn: $savePassword)
                                .controlSize(.small)
                        }
                    }
                } else {
                    GridRow {
                        Text("Private Key Path:")
                        HStack(spacing: 8) {
                            TextField("", text: $privateKeyPath)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                let panel = NSOpenPanel()
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.showsHiddenFiles = true
                                panel.title = "Select SSH Private Key"
                                panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
                                if panel.runModal() == .OK, let url = panel.url {
                                    privateKeyPath = url.path
                                }
                            } label: {
                                Image(systemName: "folder")
                                    .frame(height: 18)
                            }
                            .help("Select private key file")
                        }
                    }
                }
            }
            .padding(20)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    let finalPrivateKey = authMethod == 1 ? privateKeyPath : ""
                    let finalSavePassword = authMethod == 0 ? savePassword : false
                    
                    let updated = ConnectionProfile(
                        id: profile.id,
                        name: name,
                        host: host,
                        port: UInt16(port) ?? 22,
                        username: username,
                        privateKeyPath: finalPrivateKey,
                        savePassword: finalSavePassword
                    )
                    
                    // Only send new password if we are in Password mode and they typed something
                    let passToSave = (authMethod == 0 && finalSavePassword && !password.isEmpty) ? password : nil
                    
                    onSave(updated, passToSave)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
            }
            .padding()
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 480)
    }
}

#Preview {
    ContentView()
}

// MARK: - Animated Connecting View (Pulse Style)

struct ConnectingTerminalView: View {
    let profile: ConnectionProfile
    let errorMessage: String
    let onCancel: () -> Void
    
    @State private var isPulsing = false
    @State private var loadingTextIndex = 0
    
    let loadingMessages = [
        "Initializing secure pipeline...",
        "Negotiating cryptographic keys...",
        "Verifying host identity...",
        "Establishing data stream..."
    ]
    
    let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Central Pulsing Icon
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(ConnectionProfilePresentation.iconColor(for: profile).opacity(0.15))
                    .frame(width: 140, height: 140)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .opacity(isPulsing ? 1.0 : 0.4)
                
                // Actual Icon
                Group {
                    switch ConnectionProfilePresentation.icon(for: profile) {
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 48, weight: .light))
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 54, height: 54)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(ConnectionProfilePresentation.iconColor(for: profile).gradient)
                .clipShape(Circle())
                .shadow(color: ConnectionProfilePresentation.iconColor(for: profile).opacity(0.3), radius: 10, y: 4)
            }
            
            // Text & Progress
            VStack(spacing: 12) {
                if errorMessage.isEmpty {
                    Text(loadingMessages[loadingTextIndex])
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .scaleEffect(1.0)
                        .animation(.easeIn(duration: 0.3), value: loadingTextIndex)
                    
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                        .padding(.bottom, 4)
                    Text(errorMessage)
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            
            Spacer().frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).ignoresSafeArea())
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onReceive(timer) { _ in
            guard errorMessage.isEmpty else { return }
            withAnimation {
                loadingTextIndex = (loadingTextIndex + 1) % loadingMessages.count
            }
        }
    }
}
