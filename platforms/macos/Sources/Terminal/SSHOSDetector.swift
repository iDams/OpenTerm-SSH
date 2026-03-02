import Foundation

public enum RemotePlatform {
    case linux
    case macos
    case windows
    case unixOther
    case unknown
}

public class SSHOSDetector {
    public static func detectAndSummarize(using connection: SSHConnection) async -> String {
        return await Task.detached {
            return detect(conn: connection)
        }.value
    }
    
    private static func detect(conn: SSHConnection) -> String {
        var platform: RemotePlatform = .unknown
        
        // Paso 1: Detección
        let unameRes = (try? conn.execute("uname -s"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if unameRes == "Linux" {
            platform = .linux
        } else if unameRes == "Darwin" {
            platform = .macos
        } else if !unameRes.isEmpty && (unameRes.contains("BSD") || unameRes == "SunOS") {
            platform = .unixOther
        } else {
            // Intentos para Windows
            let cmdVer = (try? conn.execute("cmd /c ver"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if cmdVer.lowercased().contains("windows") {
                platform = .windows
            } else {
                let psVer = (try? conn.execute("powershell -NoProfile -Command \"$PSVersionTable.PSVersion.ToString()\""))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !psVer.isEmpty && psVer.contains(".") {
                    platform = .windows
                } else if !unameRes.isEmpty {
                    platform = .unixOther
                }
            }
        }
        
        var summary = ""
        
        // Paso 2 y 3: Resumen del sistema
        switch platform {
        case .linux:
            let osRelease = (try? conn.execute("cat /etc/os-release")) ?? ""
            let prettyName = parseOSRelease(osRelease) ?? "Linux"
            summary += "Welcome to \(prettyName)\n\n"
            
            let landscapeStr = "command -v landscape-sysinfo >/dev/null 2>&1 && landscape-sysinfo || (uptime && free -h && df -h /)"
            summary += (try? conn.execute(landscapeStr)) ?? ""
            
        case .macos:
            summary += "Welcome to macOS\n\n"
            summary += (try? conn.execute("top -l 1 -s 0 | head -n 10")) ?? ""
            
        case .windows:
            summary += "Welcome to Windows\n\n"
            // Using a simple command to avoid too much text
            summary += (try? conn.execute("powershell -NoProfile -Command \"Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture\"")) ?? ""
            summary += "\n"
            summary += (try? conn.execute("powershell -NoProfile -Command \"Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free\"")) ?? ""
            
        case .unixOther:
            summary += "Welcome to UNIX (\(unameRes))\n\n"
            summary += (try? conn.execute("uptime && df -h /")) ?? ""
            
        case .unknown:
            summary += "Welcome (Unknown OS)\n\n"
            summary += (try? conn.execute("uname -a")) ?? ""
        }
        
        return summary
    }
    
    private static func parseOSRelease(_ content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("PRETTY_NAME=") {
                let val = line.dropFirst("PRETTY_NAME=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"\'"))
                return String(val)
            }
        }
        return nil
    }
}
