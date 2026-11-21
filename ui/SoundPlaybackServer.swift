import AVFoundation
import Darwin
import Foundation

/// Persistent in-process audio player and local Unix domain socket server.
///
/// Hosting playback inside the long-lived AgentSoundsMenu process avoids
/// spawning a fresh short-lived `afplay` process (and CoreAudio HAL client)
/// on every agent turn.
final class SoundPlaybackServer: NSObject, AVAudioPlayerDelegate {
    static let shared = SoundPlaybackServer()

    enum PlaybackResult: Equatable {
        case ok
        case error(String)
    }

    static var defaultSocketPath: String {
        if let explicit = ProcessInfo.processInfo.environment["AGENT_SOUND_SOCKET"] {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if lower.isEmpty || lower == "0" || lower == "off" || lower == "none" || lower == "false" {
                return ""
            }
            return trimmed
        }
        return "/tmp/agent-sound-player-\(getuid()).sock"
    }

    let socketPath: String
    private let maxConcurrentPlayers: Int
    private let stateLock = NSLock()
    private let playerQueue = DispatchQueue(label: "com.gabo.agent-sounds-menu.audio-player")
    private let acceptQueue = DispatchQueue(label: "com.gabo.agent-sounds-menu.socket-accept", qos: .userInitiated)

    private var activePlayers: [AVAudioPlayer] = []
    private var serverFd: Int32 = -1
    private var isRunning = false

    init(socketPath: String = SoundPlaybackServer.defaultSocketPath, maxConcurrentPlayers: Int = 4) {
        self.socketPath = socketPath
        self.maxConcurrentPlayers = max(1, maxConcurrentPlayers)
        super.init()
    }

    @discardableResult
    func start() -> Bool {
        guard !socketPath.isEmpty else { return false }

        stateLock.lock()
        if isRunning {
            stateLock.unlock()
            return true
        }
        stateLock.unlock()

        signal(SIGPIPE, SIG_IGN)

        var addr = sockaddr_un()
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < maxPathLen else { return false }

        // Only unlink an existing path if it is already a socket file.
        removeStaleSocketIfPresent()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
            rawBuf.initializeMemory(as: UInt8.self, repeating: 0)
            for (idx, byte) in pathBytes.enumerated() {
                rawBuf[idx] = byte
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            return false
        }

        _ = Darwin.chmod(socketPath, mode_t(0o600))

        guard Darwin.listen(fd, 16) == 0 else {
            Darwin.close(fd)
            removeStaleSocketIfPresent()
            return false
        }

        stateLock.lock()
        serverFd = fd
        isRunning = true
        stateLock.unlock()

        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenFd: fd)
        }
        return true
    }

    func stop() {
        stateLock.lock()
        let fd = serverFd
        serverFd = -1
        isRunning = false
        stateLock.unlock()

        if fd >= 0 {
            _ = Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
        removeStaleSocketIfPresent()

        playerQueue.sync {
            for player in activePlayers {
                player.stop()
            }
            activePlayers.removeAll()
        }
    }

    @discardableResult
    func play(path: String, volume: Float = 0.45) -> PlaybackResult {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .error("empty clip path")
        }

        let url = URL(fileURLWithPath: trimmed)
        if url.pathExtension.lowercased() == "ogg" {
            return .error("unsupported format: ogg")
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return .error("clip not found")
        }

        let clampedVolume = min(max(volume, 0.0), 1.0)

        return playerQueue.sync {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                player.volume = clampedVolume
                guard player.prepareToPlay() else {
                    return .error("failed to prepare audio player")
                }

                if activePlayers.count >= maxConcurrentPlayers {
                    let evicted = activePlayers.removeFirst()
                    evicted.stop()
                }

                guard player.play() else {
                    return .error("failed to start playback")
                }
                activePlayers.append(player)
                return .ok
            } catch {
                return .error(error.localizedDescription)
            }
        }
    }

    func handleRequestLine(_ line: String) -> String {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clip = json["clip"] as? String else {
            return "ERR invalid json\n"
        }

        let volume: Float
        if let num = json["volume"] as? NSNumber {
            volume = num.floatValue
        } else if let str = json["volume"] as? String, let parsed = Float(str) {
            volume = parsed
        } else {
            volume = 0.45
        }

        switch play(path: clip, volume: volume) {
        case .ok:
            return "OK\n"
        case .error(let reason):
            let sanitized = reason.replacingOccurrences(of: "\n", with: " ")
            return "ERR \(sanitized)\n"
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playerQueue.async { [weak self] in
            self?.activePlayers.removeAll { $0 === player }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        playerQueue.async { [weak self] in
            self?.activePlayers.removeAll { $0 === player }
        }
    }

    // MARK: - Private Socket Helpers

    private func removeStaleSocketIfPresent() {
        guard !socketPath.isEmpty else { return }
        var st = stat()
        if Darwin.lstat(socketPath, &st) == 0 && (st.st_mode & S_IFMT) == S_IFSOCK {
            _ = Darwin.unlink(socketPath)
        }
    }

    private func acceptLoop(listenFd: Int32) {
        while true {
            stateLock.lock()
            let stillRunning = isRunning && serverFd == listenFd
            stateLock.unlock()
            if !stillRunning { break }

            let clientFd = Darwin.accept(listenFd, nil, nil)
            if clientFd < 0 {
                if errno == EINTR { continue }
                stateLock.lock()
                let active = isRunning
                stateLock.unlock()
                if !active { break }
                continue
            }

            handleClient(clientFd)
        }
    }

    private func handleClient(_ clientFd: Int32) {
        defer { Darwin.close(clientFd) }

        var nosigpipe: Int32 = 1
        _ = Darwin.setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        _ = Darwin.setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = Darwin.setsockopt(clientFd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        let maxRequestBytes = 8192

        while received.count < maxRequestBytes {
            let n = Darwin.read(clientFd, &chunk, chunk.count)
            if n > 0 {
                received.append(contentsOf: chunk[0..<n])
                if received.contains(0x0A) { // '\n'
                    break
                }
            } else {
                break
            }
        }

        let line = String(data: received, encoding: .utf8)?
            .components(separatedBy: .newlines)
            .first ?? ""
        let response = handleRequestLine(line)

        if let respData = response.data(using: .utf8) {
            respData.withUnsafeBytes { rawBuf in
                if let base = rawBuf.baseAddress {
                    _ = Darwin.write(clientFd, base, respData.count)
                }
            }
        }
    }
}
