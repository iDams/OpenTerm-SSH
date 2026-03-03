import SwiftUI
import Observation

enum NavigationItem: String, CaseIterable, Identifiable {
    case hosts = "Hosts"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .hosts: return "server.rack"
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
    @State private var selectedTab = 0
    @State private var viewLayout = ViewLayoutType.grid
    
    enum ViewLayoutType {
        case grid
        case list
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedNavItem) {
                ForEach(NavigationItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
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
                
                // Active Tab Content
                ZStack {
                    Color(NSColor.textBackgroundColor).ignoresSafeArea()
                    
                    if !tabs.contains(where: { $0.id == activeTabId }) {
                        // Fallback in case state got corrupted
                        hostsMainView
                    } else {
                        ForEach(tabs, id: \.id) { tab in
                            let isActive = (tab.id == activeTabId)
                            
                            Group {
                                switch tab {
                                case .home:
                                    hostsMainView
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
                                    connectedDetailView(conn: conn)
                                }
                            }
                            // Keep it in the view hierarchy, but hide/disable it if inactive
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                            // zIndex ensures the active tab is always on top to receive input
                            .zIndex(isActive ? 1 : 0)
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
    
    // MARK: - Hosts Grid View
    
    @ViewBuilder
    private var hostsMainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Secondary Toolbar inside detail view
            HStack {
                Button(action: { showNewHostSheet = true }) {
                    Label("New Host", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(NSColor.controlColor))
                .foregroundStyle(.primary)

                Button(action: {
                    let newLocalId = UUID()
                    let localTab = TabType.local(newLocalId)
                    tabs.append(localTab)
                    activeTabId = newLocalId
                }) {
                    Label("Terminal", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                
                Button(action: { showComingSoon = true }) {
                    Label("Serial", systemImage: "cable.connector")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                // Search field inline
                TextField("Search hosts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                
                // Estilo vista
                HStack(spacing: 0) {
                    Button(action: { viewLayout = .grid }) {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .background(viewLayout == .grid ? Color.primary.opacity(0.1) : Color.clear)
                    .foregroundStyle(viewLayout == .grid ? .primary : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    Button(action: { viewLayout = .list }) {
                        Image(systemName: "list.bullet")
                    }
                    .buttonStyle(.borderless)
                    .padding(6)
                    .background(viewLayout == .list ? Color.primary.opacity(0.1) : Color.clear)
                    .foregroundStyle(viewLayout == .list ? .primary : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding()
            
            Text("Hosts")
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)
            
            ScrollView {
                if filteredProfiles.isEmpty {
                    VStack {
                        Spacer(minLength: 100)
                        Image(systemName: "server.rack")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("No hosts saved")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if viewLayout == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)], spacing: 16) {
                            ForEach(filteredProfiles) { profile in
                                hostCard(for: profile)
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredProfiles) { profile in
                                hostCard(for: profile)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func hostCard(for profile: ConnectionProfile) -> some View {
        let isProfileConnecting = connectingProfiles.contains(profile.id)
        HostCardView(
            profile: profile,
            isConnecting: isProfileConnecting,
            onConnect: {
                guard !isProfileConnecting else { return }
                Task { await applyProfileAndConnect(profile) }
            },
            onEdit: {
                editingProfile = profile
            },
            onDuplicate: {
                Task { await profileStore.duplicateProfile(profile) }
            },
            onDelete: {
                Task { await profileStore.deleteProfile(profile) }
            }
        )
    }
    
    var filteredProfiles: [ConnectionProfile] {
        if searchText.isEmpty {
            return profileStore.profiles
        } else {
            return profileStore.profiles.filter { profile in
                profile.name.localizedCaseInsensitiveContains(searchText) ||
                profile.host.localizedCaseInsensitiveContains(searchText) ||
                profile.username.localizedCaseInsensitiveContains(searchText)
            }
        }
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
    private func connectedDetailView(conn: SSHConnection) -> some View {
        ZStack(alignment: .bottomTrailing) {
            // Terminal view
            terminalView(conn: conn)
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)
            
            // SFTP view - only mount when needed to avoid racing with terminal channel
            if selectedTab == 1 {
                SFTPView(connection: conn)
            }
            
            // Floating toggle capsule
            HStack(spacing: 2) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 0 } }) {
                    Image(systemName: "terminal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selectedTab == 0 ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(selectedTab == 0 ? Color.accentColor : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 } }) {
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
    private func terminalView(conn: SSHConnection) -> some View {
        VStack(spacing: 0) {
            SSHTerminalContainerView(connection: conn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            
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
            
            await MainActor.run {
                if Task.isCancelled {
                    conn.disconnect()
                    return
                }
                
                // Replace connecting tab with connected tab
                withAnimation {
                    if let index = tabs.firstIndex(where: { $0.id == tabId }) {
                        tabs[index] = .ssh(conn, tabId)
                    }
                }
                connectingProfiles.remove(profile.id)
                connectionTasks.removeValue(forKey: tabId)
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
}

// MARK: - Host Card View Component

struct HostCardView: View {
    let profile: ConnectionProfile
    let isConnecting: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(iconColor.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("ssh, \(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 8)
                }
                
                // Show standard Edit/Delete menu on hover
                Menu {
                    Button("Edit", action: onEdit)
                    Button("Duplicate", action: onDuplicate)
                    Divider()
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isHovering ? 1.0 : 0.0) // Only show when hovering
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(isHovering ? 0.08 : 0.04), radius: isHovering ? 5 : 3, y: isHovering ? 3 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Standard macOS right-click / two-finger tap menu
            Button("Connect", action: onConnect)
            Divider()
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private var iconName: String {
        let name = profile.name.lowercased()
        if name.contains("mac") || name.contains("apple") { return "applelogo" }
        if name.contains("win") { return "window.casement" }
        if name.contains("ubuntu") || name.contains("linux") { return "terminal" }
        if name.contains("pi") || name.contains("rasp") { return "cpu" }
        return "server.rack"
    }
    
    private var iconColor: Color {
        let name = profile.name.lowercased()
        if name.contains("mac") || name.contains("apple") { return .gray }
        if name.contains("win") { return .blue }
        if name.contains("ubuntu") { return .orange }
        if name.contains("linux") { return .yellow }
        if name.contains("pi") || name.contains("rasp") { return .red }
        return .indigo
    }
}

#Preview("HostCard Components") {
    VStack(spacing: 20) {
        HostCardView(
            profile: ConnectionProfile(name: "Production Linux", host: "10.0.0.5", port: 22, username: "root", privateKeyPath: "", savePassword: true),
            isConnecting: false,
            onConnect: {},
            onEdit: {},
            onDuplicate: {},
            onDelete: {}
        )
        HostCardView(
            profile: ConnectionProfile(name: "My Mac", host: "localhost", port: 22, username: "marco", privateKeyPath: "", savePassword: false),
            isConnecting: true,
            onConnect: {},
            onEdit: {},
            onDuplicate: {},
            onDelete: {}
        )
    }
    .padding()
    .frame(width: 350)
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

// MARK: - Animated Binary Connecting View

struct ConnectingTerminalView: View {
    let profile: ConnectionProfile
    let errorMessage: String
    let onCancel: () -> Void
    
    @State private var binaryLines: [String] = []
    let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            Spacer()
            
            // Subtle animated binary or dot matrix
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(binaryLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.green.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .frame(width: 320, height: 80, alignment: .bottomLeading)
            .clipped()
            
            Spacer().frame(height: 30)
            
            if errorMessage.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 8)
                
                Text("Negotiating link to \(profile.username)@\(profile.host)...")
                    .font(.headline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.red)
                    .padding(.bottom, 8)
                Text(errorMessage)
                    .font(.headline)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            Spacer().frame(height: 20)
            
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).ignoresSafeArea())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .onReceive(timer) { _ in
            guard errorMessage.isEmpty else { return }
            let newLine = (0..<40).map { _ in ["0", "1", " ", " ", " "].randomElement()! }.joined()
            binaryLines.append(newLine)
            if binaryLines.count > 5 {
                binaryLines.removeFirst()
            }
        }
        .onAppear {
            for _ in 0..<5 {
                binaryLines.append("")
            }
        }
    }
}
