import SwiftUI

enum HostsViewLayoutType: String, CaseIterable, Identifiable {
    case grid
    case list
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .grid: return "Grid"
        case .list: return "List"
        }
    }
    
    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct HostsHomeView: View {
    let profileStore: ConnectionProfileStore
    @Binding var searchText: String
    @Binding var viewLayout: HostsViewLayoutType
    @Binding var selectedProfileID: ConnectionProfile.ID?
    let connectingProfiles: Set<UUID>
    let onCreateHost: () -> Void
    let onOpenLocalTerminal: () -> Void
    let onConnect: (ConnectionProfile) -> Void
    let onEdit: (ConnectionProfile) -> Void
    let onDuplicate: (ConnectionProfile) -> Void
    let onDelete: (ConnectionProfile) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hostsHeroSection
                hostsContentSection
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .background(hostsBackground)
    }
    
    private var filteredProfiles: [ConnectionProfile] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return profileStore.profiles
        }
        return profileStore.profiles.filter { profile in
            profile.name.localizedCaseInsensitiveContains(query) ||
            profile.host.localizedCaseInsensitiveContains(query) ||
            profile.username.localizedCaseInsensitiveContains(query)
        }
    }
    
    private var hostsHeroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hosts")
                        .font(.system(size: 30, weight: .semibold))
                    
                    Text(hostsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    statPill(title: "Saved", value: "\(profileStore.profiles.count)")
                    statPill(title: "Showing", value: "\(filteredProfiles.count)")
                }
            }
            
            HStack(spacing: 10) {
                Label(searchSummary, systemImage: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(action: onOpenLocalTerminal) {
                        Label("Open Local Terminal", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: onCreateHost) {
                        Label("Add Host", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.12),
                            Color(NSColor.controlBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var hostsContentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(viewLayout == .grid ? "Host Cards" : "Host List")
                    .font(.headline)
                
                Spacer()
                
                if !filteredProfiles.isEmpty {
                    Text("\(filteredProfiles.count) result\(filteredProfiles.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            if filteredProfiles.isEmpty {
                emptyHostsState
            } else if viewLayout == .grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 380), spacing: 18)], spacing: 18) {
                    ForEach(filteredProfiles) { profile in
                        HostCardView(
                            profile: profile,
                            isConnecting: connectingProfiles.contains(profile.id),
                            isListStyle: false,
                            onConnect: { onConnect(profile) },
                            onEdit: { onEdit(profile) },
                            onDuplicate: { onDuplicate(profile) },
                            onDelete: { onDelete(profile) }
                        )
                    }
                }
            } else {
                hostTable
            }
        }
    }
    
    private var hostTable: some View {
        Table(filteredProfiles, selection: $selectedProfileID) {
            TableColumn("Name") { profile in
                HStack(spacing: 10) {
                    Image(systemName: ConnectionProfilePresentation.iconName(for: profile))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(ConnectionProfilePresentation.iconColor(for: profile).gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(profile.host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
                .contextMenu {
                    tableContextMenu(for: profile)
                }
            }
            .width(min: 240, ideal: 320)
            
            TableColumn("User") { profile in
                Text(profile.username)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            
            TableColumn("Port") { profile in
                Text("\(profile.port)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(70)
            
            TableColumn("Auth") { profile in
                Text(ConnectionProfilePresentation.authLabel(for: profile))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(profile.privateKeyPath.isEmpty ? Color.orange : Color.green)
            }
            .width(90)
            
            TableColumn("Status") { profile in
                if connectingProfiles.contains(profile.id) {
                    Label("Connecting", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .width(110)
            
            TableColumn("Actions") { profile in
                HStack(spacing: 8) {
                    Button(connectingProfiles.contains(profile.id) ? "Connecting..." : "Connect") {
                        onConnect(profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(connectingProfiles.contains(profile.id))
                    
                    Menu {
                        tableContextMenu(for: profile)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .width(min: 150, ideal: 170)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(minHeight: 360)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func tableContextMenu(for profile: ConnectionProfile) -> some View {
        Button("Connect") {
            onConnect(profile)
        }
        Divider()
        Button("Edit") {
            onEdit(profile)
        }
        Button("Duplicate") {
            onDuplicate(profile)
        }
        Divider()
        Button("Delete", role: .destructive) {
            onDelete(profile)
        }
    }
    
    private var emptyHostsState: some View {
        VStack(spacing: 14) {
            Image(systemName: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "server.rack" : "magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No hosts saved" : "No results")
                .font(.headline)
            
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? "Create your first SSH profile to start connecting faster."
                 : "Try a different name, host, or username.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Create Host" : "Clear Search") {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onCreateHost()
                } else {
                    searchText = ""
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private var hostsSubtitle: String {
        if profileStore.profiles.isEmpty {
            return "Save SSH hosts, launch sessions quickly, and keep connection details organized."
        }
        return "Your SSH workspace with quick access to terminals, credentials, and saved destinations."
    }
    
    private var searchSummary: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return "Search by name, host, or username from the toolbar."
        }
        return "Filtering results for “\(query)”"
    }
    
    private var hostsBackground: some View {
        LinearGradient(
            colors: [
                Color(NSColor.windowBackgroundColor),
                Color.accentColor.opacity(0.035),
                Color(NSColor.textBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
