import Foundation
import Network
import OpenTermCore

public enum SSHError: LocalizedError {
    case connectionFailed(String?)
    case authenticationFailed(String?)
    case commandFailed(String?)
    case sftpFailed(String?)
    case hostkeyRejected
    case hostkeySaveFailed
    case unknown(Int32, String?)
    
    init(code: Int32, detail: String? = nil) {
        switch code {
        case 0, -5: self = .connectionFailed(detail)
        case -4: self = .authenticationFailed(detail)
        case -1: self = .commandFailed(detail)
        case -7: self = .sftpFailed(detail)
        default: self = .unknown(code, detail)
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail):
            return sshDetailMessage(prefix: "Connection failed", detail: detail)
        case .authenticationFailed(let detail):
            return sshDetailMessage(prefix: "Authentication failed", detail: detail)
        case .commandFailed(let detail):
            return sshDetailMessage(prefix: "Command execution failed", detail: detail)
        case .sftpFailed(let detail):
            return sshDetailMessage(prefix: "SFTP operation failed", detail: detail)
        case .hostkeyRejected:
            return "Host key rejected"
        case .hostkeySaveFailed:
            return "Failed to save host key"
        case .unknown(let code, let detail):
            return sshDetailMessage(prefix: "SSH error (code \(code))", detail: detail)
        }
    }
}

private func sshDetailMessage(prefix: String, detail: String?) -> String {
    guard let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return prefix
    }
    return "\(prefix): \(detail)"
}

@inline(__always)
private func sshErrorCode(_ error: term_ssh_error_t) -> Int32 {
    error.rawValue
}

public enum SSHHostKeyState: Sendable {
    case ok
    case new
    case changed
    case other
    case fileNotFound
}

public enum SSHHostKeyDecision: Sendable {
    case reject
    case acceptOnce
    case acceptAndSave
}

public enum SSHKeyType: Sendable {
    case unknown
    case rsa
    case ecdsa
    case ed25519
    case rsaCert
    case ecdsaCert
    case ed25519Cert
}

public struct SSHHostKeyInfo: Sendable {
    public let state: SSHHostKeyState
    public let host: String
    public let port: UInt16
    public let keyType: SSHKeyType
    public let fingerprintSHA256: String?
    public let fingerprintMD5: String?
    
    public var hostKeyIdentifier: String {
        "\(host):\(port)"
    }
}

public typealias SSHHostKeyCallback = @MainActor (SSHHostKeyInfo) async -> SSHHostKeyDecision

private final class HostKeyCallbackBridge: @unchecked Sendable {
    weak var connection: SSHConnection?
    var callback: SSHHostKeyCallback?
    var pendingDecision: SSHHostKeyDecision?
    let semaphore = DispatchSemaphore(value: 0)
    
    func requestDecision(info: SSHHostKeyInfo) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let callback = self.callback else {
                self?.signal(decision: .reject)
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let decision = await callback(info)
                self.signal(decision: decision)
            }
        }
    }
    
    func waitForDecision() -> SSHHostKeyDecision {
        let result = semaphore.wait(timeout: .now() + 60)
        if result == .timedOut {
            return .reject
        }
        return pendingDecision ?? .reject
    }
    
    func signal(decision: SSHHostKeyDecision) {
        pendingDecision = decision
        semaphore.signal()
    }
}

public final class SSHConnection: @unchecked Sendable {
    public let host: String
    public let port: UInt16
    public let username: String
    
    private(set) var rawPointer: OpaquePointer?
    private var sessionPointer: OpaquePointer?
    private var callbackBridge: HostKeyCallbackBridge?
    private var lastLogMessage: String?
    public let lock = NSRecursiveLock()
    
    public init(host: String, port: UInt16 = 22, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }
    
    private var activeChannel: InteractiveSSHChannel?
    
    func registerChannel(_ channel: InteractiveSSHChannel) {
        activeChannel = channel
    }
    
    /// Pause the interactive channel polling so SFTP can safely use the session
    func pauseChannel() {
        activeChannel?.pause()
    }
    
    /// Resume the interactive channel polling after SFTP is done
    func resumeChannel() {
        activeChannel?.resume()
    }
    
    private static func tcpPreflight(host: String, port: UInt16, timeout: TimeInterval = 3) -> String? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return "Invalid TCP port \(port)"
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.openterm.ssh.preflight", qos: .userInitiated)
        let lock = NSLock()
        var finished = false
        var failure: String?

        connection.stateUpdateHandler = { state in
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }

            switch state {
            case .ready:
                finished = true
                semaphore.signal()
            case .failed(let error):
                failure = error.localizedDescription
                finished = true
                semaphore.signal()
            case .cancelled:
                finished = true
                semaphore.signal()
            default:
                break
            }
        }

        connection.start(queue: queue)
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        connection.cancel()

        if waitResult == .timedOut {
            return "TCP preflight timed out"
        }

        return failure
    }

    public func connectAsync(password: String? = nil,
                             privateKey: String? = nil,
                             hostKeyCallback: SSHHostKeyCallback? = nil) async throws {
        let bridge = HostKeyCallbackBridge()
        bridge.connection = self
        bridge.callback = hostKeyCallback

        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: SSHError.connectionFailed(nil))
                    return
                }

                do {
                    try self.connectSync(password: password, privateKey: privateKey, bridge: bridge)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func connectSync(password: String?,
                             privateKey: String?,
                             bridge: HostKeyCallbackBridge) throws {
        lock.lock()
        defer { lock.unlock() }
        
        disconnectInternal()
        lastLogMessage = nil
        
        guard let session = term_ssh_session_new() else {
            throw SSHError.connectionFailed(nil)
        }

        term_ssh_session_set_log_level(session, TERM_SSH_LOG_INFO)
        term_ssh_session_set_log_callback(session, { _, message, userdata in
            guard let userdata, let message else { return }
            let connection = Unmanaged<SSHConnection>.fromOpaque(userdata).takeUnretainedValue()
            let text = String(cString: message)
            connection.recordLogMessage(text)
            print("[SSH-C] \(text)")
        }, Unmanaged.passUnretained(self).toOpaque())

        if bridge.callback != nil {
            self.callbackBridge = bridge
            
            term_ssh_session_set_hostkey_callback(session, { state, host, port, keyType, fpSha256, fpMd5, userdata in
                guard let userdata = userdata else { return TERM_SSH_HOSTKEY_REJECT }
                let bridge = Unmanaged<HostKeyCallbackBridge>.fromOpaque(userdata).takeUnretainedValue()
                
                let info = SSHHostKeyInfo(
                    state: SSHConnection.mapHostKeyStateStatic(state),
                    host: host.map { String(cString: $0) } ?? "",
                    port: port,
                    keyType: SSHConnection.mapKeyTypeStatic(keyType),
                    fingerprintSHA256: fpSha256.map { String(cString: $0) },
                    fingerprintMD5: fpMd5.map { String(cString: $0) }
                )
                
                bridge.requestDecision(info: info)
                let decision = bridge.waitForDecision()
                return SSHConnection.mapHostKeyDecisionStatic(decision)
            }, Unmanaged.passUnretained(bridge).toOpaque())
        }



        let configStorage = SSHConfigStorage(
            host: host,
            port: port,
            username: username,
            password: password,
            privateKeyPath: privateKey
        )
        
        // withExtendedLifetime ensures ARC doesn't free configStorage
        // (and its strdup'd C strings) before term_ssh_connect finishes
        try withExtendedLifetime(configStorage) {
            var config = configStorage.config

            var connection: OpaquePointer?
            let result = term_ssh_connect(&connection, session, &config)

            if result != TERM_SSH_OK {
                term_ssh_session_free(session)
                callbackBridge = nil
                throw SSHError(code: sshErrorCode(result), detail: lastLogMessage)
            }

            sessionPointer = session
            rawPointer = connection
        }
    }
    
    private func recordLogMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastLogMessage = trimmed
    }

    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        disconnectInternal()
    }
    
    private func disconnectInternal() {
        if let conn = rawPointer {
            term_ssh_disconnect(conn)
            term_ssh_connection_free(conn)
            rawPointer = nil
        }

        if let session = sessionPointer {
            term_ssh_session_free(session)
            sessionPointer = nil
        }
        
        callbackBridge = nil
    }
    
    public func execute(_ command: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        guard let conn = rawPointer else {
            throw SSHError.connectionFailed(nil)
        }
        
        var output: UnsafeMutablePointer<CChar>?
        var outputLen: size_t = 0
        
        let result = term_ssh_execute(conn, command, &output, &outputLen)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result), detail: lastLogMessage)
        }
        
        guard let outputPtr = output else {
            return ""
        }
        
        let string = String(cString: outputPtr)
        free(outputPtr)
        
        return string
    }
    
    deinit {
        disconnect()
    }
    
    private static func mapHostKeyStateStatic(_ state: term_ssh_hostkey_state_t) -> SSHHostKeyState {
        switch state {
        case TERM_SSH_HOSTKEY_OK: return .ok
        case TERM_SSH_HOSTKEY_NEW: return .new
        case TERM_SSH_HOSTKEY_CHANGED: return .changed
        case TERM_SSH_HOSTKEY_OTHER: return .other
        case TERM_SSH_HOSTKEY_FILE_NOT_FOUND: return .fileNotFound
        default: return .new
        }
    }
    
    private static func mapKeyTypeStatic(_ type: term_ssh_key_type_t) -> SSHKeyType {
        switch type {
        case TERM_SSH_KEY_RSA: return .rsa
        case TERM_SSH_KEY_ECDSA: return .ecdsa
        case TERM_SSH_KEY_ED25519: return .ed25519
        case TERM_SSH_KEY_RSA_CERT: return .rsaCert
        case TERM_SSH_KEY_ECDSA_CERT: return .ecdsaCert
        case TERM_SSH_KEY_ED25519_CERT: return .ed25519Cert
        default: return .unknown
        }
    }
    
    private static func mapHostKeyDecisionStatic(_ decision: SSHHostKeyDecision) -> term_ssh_hostkey_decision_t {
        switch decision {
        case .reject: return TERM_SSH_HOSTKEY_REJECT
        case .acceptOnce: return TERM_SSH_HOSTKEY_ACCEPT_ONCE
        case .acceptAndSave: return TERM_SSH_HOSTKEY_ACCEPT_AND_SAVE
        }
    }
}

public struct SSHFileInfo {
    public let name: String
    public let size: UInt64
    public let isDirectory: Bool
    
    public init(name: String, size: UInt64 = 0, isDirectory: Bool = false) {
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
    }
}

public class SSHSFTP {
    private var rawPointer: OpaquePointer?
    private let connection: SSHConnection
    
    public var isConnected: Bool {
        return rawPointer != nil
    }
    
    public init(connection: SSHConnection) throws {
        self.connection = connection
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let connPtr = connection.rawPointer else {
            throw SSHError.connectionFailed(nil)
        }
        
        var sftp: OpaquePointer?
        let result = term_ssh_sftp_init(&sftp, connPtr)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
        
        rawPointer = sftp
    }
    
    public func list(_ path: String = ".") throws -> [SSHFileInfo] {
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let sftp = rawPointer else {
            throw SSHError.sftpFailed(nil)
        }
        
        var files: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var count: size_t = 0
        
        let result = term_ssh_sftp_list(sftp, path, &files, &count)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
        
        var fileList: [SSHFileInfo] = []
        
        for i in 0..<count {
            if let filePtr = files?[i], let fileName = String(cString: filePtr, encoding: .utf8) {
                fileList.append(SSHFileInfo(name: fileName))
                free(files?[i])
            }
        }
        
        free(files)
        
        return fileList
    }
    
    public func upload(localPath: String, remotePath: String) throws {
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let sftp = rawPointer else {
            throw SSHError.sftpFailed(nil)
        }
        
        let result = term_ssh_sftp_upload(sftp, localPath, remotePath, nil, nil)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
    }
    
    public func download(remotePath: String, localPath: String) throws {
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let sftp = rawPointer else {
            throw SSHError.sftpFailed(nil)
        }
        
        let result = term_ssh_sftp_download(sftp, remotePath, localPath, nil, nil)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
    }
    
    public func createDirectory(_ path: String) throws {
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let sftp = rawPointer else {
            throw SSHError.sftpFailed(nil)
        }
        
        let result = term_ssh_sftp_mkdir(sftp, path)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
    }
    
    public func remove(_ path: String) throws {
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let sftp = rawPointer else {
            throw SSHError.sftpFailed(nil)
        }
        
        let result = term_ssh_sftp_remove(sftp, path)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
    }
    
    public func rename(oldPath: String, newPath: String) throws {
        connection.pauseChannel()
        connection.lock.lock()
        defer {
            connection.lock.unlock()
            connection.resumeChannel()
        }
        
        guard let sftp = rawPointer else {
            throw SSHError.sftpFailed(nil)
        }
        
        let result = term_ssh_sftp_rename(sftp, oldPath, newPath)
        
        if result != TERM_SSH_OK {
            throw SSHError(code: sshErrorCode(result))
        }
    }
    
    public func disconnect() {
        connection.lock.lock()
        defer { connection.lock.unlock() }
        
        if let sftp = rawPointer {
            term_ssh_sftp_free(sftp)
            rawPointer = nil
        }
    }
    
    deinit {
        disconnect()
    }
}

public protocol InteractiveSSHChannelDelegate: AnyObject {
    func channel(_ channel: InteractiveSSHChannel, didReceiveData data: Data)
    func channelDidClose(_ channel: InteractiveSSHChannel)
}

public class InteractiveSSHChannel: @unchecked Sendable {
    private var rawPointer: OpaquePointer?
    private let connection: SSHConnection
    public weak var delegate: InteractiveSSHChannelDelegate?
    private let queue = DispatchQueue(label: "com.openterm.ssh.interactive", qos: .userInteractive)
    private var isRunning = false
    private var isPaused = false
    private let pauseSemaphore = DispatchSemaphore(value: 0)
    
    public init(connection: SSHConnection) throws {
        self.connection = connection
        connection.lock.lock()
        defer { connection.lock.unlock() }
        
        guard let connPtr = connection.rawPointer else {
            throw SSHError.connectionFailed(nil)
        }
        
        guard let channel = term_ssh_channel_new_interactive(connPtr) else {
            throw SSHError.commandFailed(nil)
        }
        
        self.rawPointer = OpaquePointer(channel)
        
        if term_ssh_channel_open_session_interactive(channel) != TERM_SSH_OK {
            throw SSHError.commandFailed(nil)
        }
    }
    
    public func requestPtyAndShell(terminal: String = "xterm-256color", columns: Int = 80, rows: Int = 24) throws {
        connection.lock.lock()
        defer { connection.lock.unlock() }
        
        guard let channel = rawPointer else { throw SSHError.commandFailed(nil) }
        
        if term_ssh_channel_request_pty_interactive(UnsafeMutableRawPointer(channel), terminal, Int32(columns), Int32(rows)) != TERM_SSH_OK {
            throw SSHError.commandFailed(nil)
        }
        
        if term_ssh_channel_request_shell_interactive(UnsafeMutableRawPointer(channel)) != TERM_SSH_OK {
            throw SSHError.commandFailed(nil)
        }
    }
    
    public func setWindowSize(columns: Int, rows: Int) {
        connection.lock.lock()
        defer { connection.lock.unlock() }
        
        guard let channel = rawPointer else { return }
        term_ssh_channel_change_pty_size_interactive(UnsafeMutableRawPointer(channel), Int32(columns), Int32(rows))
    }
    
    public func write(data: Data) {
        connection.lock.lock()
        defer { connection.lock.unlock() }
        
        guard let channel = rawPointer else { return }
        data.withUnsafeBytes { ptr in
            guard let baseAddr = ptr.baseAddress else { return }
            _ = term_ssh_channel_write_interactive(UnsafeMutableRawPointer(channel), baseAddr, UInt32(data.count))
        }
    }
    
    public func startReading() {
        guard !isRunning, rawPointer != nil else { return }
        isRunning = true
        connection.registerChannel(self)
        poll()
    }
    
    /// Synchronously pauses the polling loop. Blocks until the loop has fully stopped.
    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        // Wait for the polling loop to signal it has stopped (up to 2 seconds)
        _ = pauseSemaphore.wait(timeout: .now() + 2.0)
    }
    
    func resume() {
        guard isPaused else { return }
        isPaused = false
        if isRunning {
            poll()
        }
    }
    
    private func poll() {
        guard isRunning, !isPaused else {
            if isPaused { pauseSemaphore.signal() }
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // Check pause state BEFORE doing any work
            guard self.isRunning, !self.isPaused else {
                if self.isPaused { self.pauseSemaphore.signal() }
                return
            }
            
            self.connection.lock.lock()
            guard let channel = self.rawPointer else {
                self.connection.lock.unlock()
                return
            }
            
            if term_ssh_channel_is_eof_interactive(UnsafeMutableRawPointer(channel)) != 0 {
                self.connection.lock.unlock()
                self.isRunning = false
                self.delegate?.channelDidClose(self)
                return
            }
            
            self.connection.lock.unlock()
            
            // Check pause state again before the blocking network poll
            guard !self.isPaused else {
                self.pauseSemaphore.signal()
                return
            }
            
            let pollResult = term_ssh_channel_poll_timeout_interactive(UnsafeMutableRawPointer(channel), 10, 0)
            
            // Check pause state AFTER network poll returns
            guard !self.isPaused else {
                self.pauseSemaphore.signal()
                return
            }
            
            self.connection.lock.lock()
            guard let channel2 = self.rawPointer else {
                self.connection.lock.unlock()
                return
            }
            
            if pollResult < 0 || term_ssh_channel_is_eof_interactive(UnsafeMutableRawPointer(channel2)) != 0 {
                self.connection.lock.unlock()
                self.isRunning = false
                self.delegate?.channelDidClose(self)
                return
            }
            
            var moreData = false
            
            if pollResult > 0 {
                let bufferSize = 8192
                var buffer = [UInt8](repeating: 0, count: bufferSize)
                let bytesRead = term_ssh_channel_read_nonblocking_interactive(
                    UnsafeMutableRawPointer(channel2),
                    &buffer,
                    UInt32(bufferSize),
                    0
                )
                
                if bytesRead > 0 {
                    let data = Data(buffer[0..<Int(bytesRead)])
                    self.delegate?.channel(self, didReceiveData: data)
                    moreData = true
                }
            }
            
            self.connection.lock.unlock()
            
            if moreData {
                self.poll()
            } else if !self.isRunning {
                // Safely free the channel on the polling thread to prevent Use-After-Free memory crashes
                self.connection.lock.lock()
                if let finalChannel = self.rawPointer {
                    term_ssh_channel_send_eof_interactive(UnsafeMutableRawPointer(finalChannel))
                    term_ssh_channel_free_interactive(UnsafeMutableRawPointer(finalChannel))
                    self.rawPointer = nil
                }
                self.connection.lock.unlock()
            } else {
                // poll_timeout already slept up to 10ms if there was no data.
                // Re-queue immediately.
                DispatchQueue.global().async {
                    self.poll()
                }
            }
        }
    }
    
    public func close() {
        isRunning = false
    }
    
    deinit {
        close()
    }
}

private final class SSHConfigStorage {
    let config: term_ssh_config_t

    private let hostPointer: UnsafeMutablePointer<CChar>
    private let usernamePointer: UnsafeMutablePointer<CChar>
    private let passwordPointer: UnsafeMutablePointer<CChar>?
    private let privateKeyPointer: UnsafeMutablePointer<CChar>?
    private let knownHostsPointer: UnsafeMutablePointer<CChar>

    init(
        host: String,
        port: UInt16,
        username: String,
        password: String?,
        privateKeyPath: String?
    ) {
        hostPointer = strdup(host)
        usernamePointer = strdup(username)

        if let password, !password.isEmpty {
            passwordPointer = strdup(password)
        } else {
            passwordPointer = nil
        }

        let resolvedPrivateKeyPath: String?
        if let privateKeyPath, !privateKeyPath.isEmpty {
            resolvedPrivateKeyPath = privateKeyPath
        } else {
            resolvedPrivateKeyPath = defaultPrivateKeyPath()
        }

        if let resolvedPrivateKeyPath {
            privateKeyPointer = strdup(resolvedPrivateKeyPath)
        } else {
            privateKeyPointer = nil
        }

        knownHostsPointer = strdup(defaultKnownHostsPath())

        var config = term_ssh_config_t()
        config.host = UnsafePointer(hostPointer)
        config.port = port
        config.username = UnsafePointer(usernamePointer)
        config.password = passwordPointer.map { UnsafePointer($0) }
        config.private_key_path = privateKeyPointer.map { UnsafePointer($0) }
        config.passphrase = nil
        config.timeout_ms = 10000
        if let password, !password.isEmpty {
            config.auth_methods = term_ssh_auth_method_t(rawValue: TERM_SSH_AUTH_PASSWORD.rawValue | TERM_SSH_AUTH_INTERACTIVE.rawValue)
        } else {
            config.auth_methods = term_ssh_auth_method_t(rawValue: TERM_SSH_AUTH_PASSWORD.rawValue | TERM_SSH_AUTH_PUBLICKEY.rawValue | TERM_SSH_AUTH_INTERACTIVE.rawValue)
        }
        config.strict_host_key = true
        config.known_hosts_file = UnsafePointer(knownHostsPointer)

        self.config = config
    }

    deinit {
        free(hostPointer)
        free(usernamePointer)
        free(passwordPointer)
        free(privateKeyPointer)
        free(knownHostsPointer)
    }
}
