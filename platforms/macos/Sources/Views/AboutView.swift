import SwiftUI

struct AboutView: View {
    @State private var markdownText: String = "Loading licenses..."
    @Environment(\.openURL) var openURL
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 20) {
                if let nsImage = NSImage(named: "AppIcon") {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 80, height: 80)
                } else {
                    Image(systemName: "terminal.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenTerm")
                        .font(.system(size: 28, weight: .bold))
                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Copyright © 2026 OpenTerm SSH")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(30)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // License Scroll
            ScrollView {
                // SwiftUI's native Markdown support for Text since iOS 15 / macOS 12
                Text(.init(markdownText))
                    .font(.system(.body, design: .serif))
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        openURL(url)
                        return .handled
                    })
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadNotices()
        }
    }
    
    private func loadNotices() {
        if let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md") {
            do {
                markdownText = try String(contentsOf: url)
            } catch {
                markdownText = "Error loading THIRD_PARTY_NOTICES.md: \(error.localizedDescription)"
            }
        } else {
            markdownText = "THIRD_PARTY_NOTICES.md not found in bundle resources."
        }
    }
}
