import SwiftUI

enum ConnectionProfilePresentation {
    enum IconSource {
        case system(String)
        case asset(String)
    }

    static func icon(for profile: ConnectionProfile) -> IconSource {
        let os = (profile.detectedOS ?? "").lowercased()
        let name = profile.name.lowercased()
        
        if os.contains("ubuntu") { return .asset("ubuntu") }
        if os.contains("mac") || os.contains("darwin") { return .asset("apple") }
        
        if name.contains("ubuntu") { return .asset("ubuntu") }
        if name.contains("mac") || name.contains("apple") { return .asset("apple") }
        
        if name.contains("win") { return .system("window.casement") }
        if name.contains("linux") { return .system("terminal") }
        if name.contains("pi") || name.contains("rasp") { return .system("cpu") }
        
        return .system("server.rack")
    }
    
    static func iconColor(for profile: ConnectionProfile) -> Color {
        let name = profile.name.lowercased()
        let os = (profile.detectedOS ?? "").lowercased()
        
        if os.contains("ubuntu") || name.contains("ubuntu") { return Color(red: 0.89, green: 0.34, blue: 0.13) }
        if os.contains("mac") || os.contains("darwin") || name.contains("mac") || name.contains("apple") { return .gray }
        
        if name.contains("win") { return .blue }
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
        Button(action: onConnect) {
            ZStack(alignment: .top) {
                // Top-floating badges
                HStack(alignment: .top) {
                    if isConnecting {
                        connectionBadge
                    } else {
                        authBadge
                    }
                    
                    Spacer()
                    
                    hostMenu
                }
                .padding(14)
                
                // Centered content
                VStack(spacing: 12) {
                    hostIcon(size: 72, cornerRadius: 18)
                        .padding(.top, 24)
                    
                    VStack(spacing: 4) {
                        Text(profile.name)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)
                        
                        Text(profile.host)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.bottom, 12)
                    
                    Text("ssh \(profile.username)@\(profile.host)\(profile.port != 22 ? " -p \(profile.port)" : "")")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0.02), radius: isHovering ? 8 : 2, y: isHovering ? 4 : 1)
    }
    
    private var listBody: some View {
        Button(action: onConnect) {
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
                    hostMenu
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
        .background(cardBackground)
        .overlay(cardBorder)
    }
    
    private func hostIcon(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            switch ConnectionProfilePresentation.icon(for: profile) {
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.42, weight: .medium))
            case .asset(let name):
                Image(name)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.46, height: size * 0.46)
            }
        }
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
            Image(systemName: "ellipsis")
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
            .stroke(isHovering ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.06), lineWidth: isHovering ? 1.5 : 1)
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
            profile: ConnectionProfile(name: "My Mac", host: "localhost", port: 22, username: "user", privateKeyPath: "", savePassword: false),
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
