import Foundation
import Observation

struct ConnectionProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: UInt16
    var username: String
    var privateKeyPath: String
    var savePassword: Bool
    var detectedOS: String?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 22,
        username: String,
        privateKeyPath: String = "",
        savePassword: Bool = false,
        detectedOS: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.privateKeyPath = privateKeyPath
        self.savePassword = savePassword
        self.detectedOS = detectedOS
    }
}

@MainActor
@Observable
final class ConnectionProfileStore {
    private(set) var profiles: [ConnectionProfile] = []

    private let fileURL: URL
    private let keychain = KeychainManager.shared

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("OpenTerm", isDirectory: true)
        self.fileURL = directory.appendingPathComponent("profiles.json")
        load(fileManager: fileManager)
    }

    func saveProfile(_ profile: ConnectionProfile, password: String? = nil) async {
        var updatedProfile = profile
        updatedProfile.name = updatedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedProfile.host = updatedProfile.host.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedProfile.username = updatedProfile.username.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedProfile.privateKeyPath = updatedProfile.privateKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let password = password, !password.isEmpty, updatedProfile.savePassword {
            do {
                try await keychain.savePassword(password, forProfileID: updatedProfile.id)
            } catch {
                updatedProfile.savePassword = false
            }
        }
        
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = updatedProfile
        } else {
            profiles.append(updatedProfile)
        }

        profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }
    
    func getSavedPassword(for profile: ConnectionProfile) async -> String? {
        do {
            return try await keychain.getPassword(forProfileID: profile.id)
        } catch {
            return nil
        }
    }

    func deleteProfiles(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        persist()
    }
    
    func deleteProfile(_ profile: ConnectionProfile) async {
        profiles.removeAll { $0.id == profile.id }
        do {
            try await keychain.deletePassword(forProfileID: profile.id)
        } catch {}
        persist()
    }
    
    func duplicateProfile(_ profile: ConnectionProfile) async {
        var newProfile = profile
        newProfile.id = UUID()
        newProfile.name = "\(profile.name) Copy"
        
        let existingPassword = await getSavedPassword(for: profile)
        await saveProfile(newProfile, password: existingPassword)
    }

    private func load(fileManager: FileManager) {
        guard let data = try? Data(contentsOf: fileURL) else {
            return
        }

        do {
            profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        } catch {
            profiles = []
        }
    }

    private func persist(fileManager: FileManager = .default) {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: fileURL, options: .atomic)
        } catch {
        }
    }
}