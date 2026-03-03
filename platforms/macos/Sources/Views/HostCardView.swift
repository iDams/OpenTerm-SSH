import SwiftUI

enum ConnectionProfilePresentation {
    static func iconName(for profile: ConnectionProfile) -> String {
        let name = profile.name.lowercased()
        if name.contains("mac") || name.contains("apple") { return "applelogo" }
        if name.contains("win") { return "window.casement" }
        if name.contains("ubuntu") || name.contains("linux") { return "terminal" }
        if name.contains("pi") || name.contains("rasp") { return "cpu" }
        return "server.rack"
    }
    
    static func iconColor(for profile: ConnectionProfile) -> Color {
        let name = profile.name.lowercased()
        if name.contains("mac") || name.contains("apple") { return .gray }
        if name.contains("win") { return .blue }
        if name.contains("ubuntu") { return .orange }
        if name.contains("linux") { return .yellow }
        if name.contains("pi") || name.contains("rasp") { return .red }
        return .indigo
    }
    
    static func authLabel(for profile: ConnectionProfile) -> String {
        profile.privateKeyPath.isEmpty ? "Password" : "SSH Key"
    }
}

struct HostCardView: View {
    let profile: ConnectionProfile
    let isConnecting: Bool
    let isListStyle: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Group {
            if isListStyle {
                listBody
            } else {
                gridBody
            }
        }
        .contextMenu {
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
    
    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                hostIcon(size: 50, cornerRadius: 14)
                
                Spacer()
                
                HStack(spacing: 8) {
                    if isConnecting {
                        connectionBadge
                    } else {
                        authBadge
                    }
                    hostMenu
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(profile.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                
                Text(secondarySummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            HStack(spacing: 0) {
                Button(action: onConnect) {
                    Label(isConnecting ? "Connecting..." : "Connect", systemImage: isConnecting ? "hourglass" : "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0.05), radius: isHovering ? 10 : 4, y: isHovering ? 6 : 2)
    }
    
    private var listBody: some View {
        HStack(spacing: 14) {
            hostIcon(size: 42, cornerRadius: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(profile.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                
                Text(secondarySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 12)
            
            HStack(spacing: 10) {
                if isConnecting {
                    connectionBadge
                } else {
                    authBadge
                }
            }
            
            Button(action: onConnect) {
                Label(isConnecting ? "Connecting..." : "Connect", systemImage: isConnecting ? "hourglass" : "arrow.right.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
            
            hostMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
    }
    
    private func hostIcon(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(systemName: ConnectionProfilePresentation.iconName(for: profile))
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ConnectionProfilePresentation.iconColor(for: profile).gradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
    
    private var hostMenu: some View {
        Menu {
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering || isListStyle ? 1.0 : 0.75)
    }
    
    private var authBadge: some View {
        Text(ConnectionProfilePresentation.authLabel(for: profile))
            .font(.caption.weight(.medium))
            .foregroundStyle(profile.privateKeyPath.isEmpty ? Color.orange : Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((profile.privateKeyPath.isEmpty ? Color.orange : Color.green).opacity(0.12), in: Capsule())
    }
    
    private var connectionBadge: some View {
        Label("Connecting", systemImage: "arrow.trianglehead.2.clockwise")
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
    
    private var secondarySummary: String {
        if profile.port == 22 {
            return profile.username
        }
        return "\(profile.username) · :\(profile.port)"
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(NSColor.controlBackgroundColor))
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.primary.opacity(isHovering ? 0.10 : 0.05), lineWidth: 1)
    }
}

#Preview("HostCard Components") {
    VStack(spacing: 20) {
        HostCardView(
            profile: ConnectionProfile(name: "Production Linux", host: "10.0.0.5", port: 22, username: "root", privateKeyPath: "", savePassword: true),
            isConnecting: false,
            isListStyle: false,
            onConnect: {},
            onEdit: {},
            onDuplicate: {},
            onDelete: {}
        )
        HostCardView(
            profile: ConnectionProfile(name: "My Mac", host: "localhost", port: 22, username: "marco", privateKeyPath: "", savePassword: false),
            isConnecting: true,
            isListStyle: true,
            onConnect: {},
            onEdit: {},
            onDuplicate: {},
            onDelete: {}
        )
    }
    .padding()
    .frame(width: 350)
}
