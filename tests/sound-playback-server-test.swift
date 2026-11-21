import Darwin
import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message): expected=\(expected) actual=\(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

/// Write a tiny valid 44.1 kHz 16-bit mono silent WAV clip (~25 ms).
func writeSilentWav(to url: URL) throws {
    let sampleRate: UInt32 = 44100
    let numSamples: UInt32 = 1102
    let dataSize: UInt32 = numSamples * 2
    let chunkSize: UInt32 = 36 + dataSize

    var data = Data()
    func appendLE(_ value: UInt32) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 4))
    }
    func appendLE16(_ value: UInt16) {
        var v = value.littleEndian
        data.append(Data(bytes: &v, count: 2))
    }

    data.append("RIFF".data(using: .ascii)!)
    appendLE(chunkSize)
    data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!)
    appendLE(16)         // PCM subchunk size
    appendLE16(1)        // PCM format
    appendLE16(1)        // Mono
    appendLE(sampleRate)
    appendLE(sampleRate * 2) // Byte rate
    appendLE16(2)        // Block align
    appendLE16(16)       // Bits per sample
    data.append("data".data(using: .ascii)!)
    appendLE(dataSize)
    data.append(Data(count: Int(dataSize)))

    try data.write(to: url)
}

func sendSocketRequest(socketPath: String, payload: String) -> String {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    assertTrue(fd >= 0, "client socket creation failed")
    defer { Darwin.close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8)
    withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
        rawBuf.initializeMemory(as: UInt8.self, repeating: 0)
        for (i, b) in bytes.enumerated() {
            rawBuf[i] = b
        }
    }

    let rc = withUnsafePointer(to: &addr) { ptr -> Int32 in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    assertEqual(rc, 0, "client connect failed (errno=\(errno))")

    let reqData = (payload + "\n").data(using: .utf8)!
    reqData.withUnsafeBytes { rawBuf in
        _ = Darwin.write(fd, rawBuf.baseAddress!, reqData.count)
    }

    var buf = [UInt8](repeating: 0, count: 512)
    let n = Darwin.read(fd, &buf, buf.count)
    assertTrue(n > 0, "expected non-empty response from socket")
    return String(bytes: buf[0..<n], encoding: .utf8) ?? ""
}

@main
struct SoundPlaybackServerTestMain {
    static func main() throws {
        let tmpDir = URL(fileURLWithPath: "/tmp/acs-swift-\(getpid())")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sockPath = tmpDir.appendingPathComponent("player.sock").path
        let wavURL = tmpDir.appendingPathComponent("silent.wav")
        try writeSilentWav(to: wavURL)
        let oggURL = tmpDir.appendingPathComponent("fake.ogg")
        try Data().write(to: oggURL)

        let server = SoundPlaybackServer(socketPath: sockPath, maxConcurrentPlayers: 2)
        assertTrue(server.start(), "server.start() should succeed")

        // Verify socket exists and is user-only (0600)
        var st = stat()
        assertEqual(Darwin.lstat(sockPath, &st), 0, "socket file should exist")
        assertEqual(st.st_mode & S_IFMT, S_IFSOCK, "path should be a Unix socket")
        assertEqual(st.st_mode & 0o777, mode_t(0o600), "socket permissions should be 0600")

        // Valid WAV request via socket
        let okResp = sendSocketRequest(
            socketPath: sockPath,
            payload: "{\"clip\":\"\(wavURL.path)\",\"volume\":0.05}"
        )
        assertEqual(okResp, "OK\n", "valid WAV should return OK")

        // Unsupported .ogg should return ERR so shell falls back to ffplay
        let oggResp = sendSocketRequest(
            socketPath: sockPath,
            payload: "{\"clip\":\"\(oggURL.path)\",\"volume\":0.45}"
        )
        assertTrue(oggResp.hasPrefix("ERR "), "ogg should return ERR, got: \(oggResp)")

        // Missing file should return ERR
        let missingResp = sendSocketRequest(
            socketPath: sockPath,
            payload: "{\"clip\":\"\(tmpDir.path)/missing.wav\",\"volume\":0.45}"
        )
        assertTrue(missingResp.hasPrefix("ERR "), "missing file should return ERR, got: \(missingResp)")

        // Invalid JSON should return ERR
        let badJsonResp = sendSocketRequest(socketPath: sockPath, payload: "not-json")
        assertTrue(badJsonResp.hasPrefix("ERR "), "invalid json should return ERR, got: \(badJsonResp)")

        // Stop server and verify socket cleanup
        server.stop()
        assertEqual(Darwin.lstat(sockPath, &st), -1, "socket file should be removed on stop()")

        print("sound-playback-server-test: ALL PASS")
    }
}
