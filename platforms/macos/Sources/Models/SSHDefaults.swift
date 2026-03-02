import Foundation

func defaultKnownHostsPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/.ssh/known_hosts"
}

func defaultPrivateKeyPath() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let candidates = [
        ".ssh/id_ed25519",
        ".ssh/id_ecdsa",
        ".ssh/id_rsa",
    ]

    for candidate in candidates {
        let fullPath = "\(home)/\(candidate)"
        if FileManager.default.isReadableFile(atPath: fullPath) {
            return fullPath
        }
    }

    return nil
}
