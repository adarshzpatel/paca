import Foundation

/// A blocking unix-domain stream socket that speaks newline-delimited frames.
/// Reads run on a dedicated thread; writes are serialized by a lock.
final class LineSocket: @unchecked Sendable {
    private let fd: Int32
    private let writeLock = NSLock()
    private var closed = false

    init(path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrError.socket("socket() failed: errno \(errno)") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else {
            Darwin.close(fd)
            throw HerdrError.socket("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: path.utf8)
            raw[path.utf8.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard result == 0 else {
            let code = errno
            Darwin.close(fd)
            throw HerdrError.notRunning(path: path, errno: code)
        }
        self.fd = fd
    }

    func send(_ line: Data) throws {
        var frame = line
        frame.append(0x0A)
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { throw HerdrError.disconnected }
        try frame.withUnsafeBytes { buf in
            var offset = 0
            while offset < buf.count {
                let n = write(fd, buf.baseAddress! + offset, buf.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw HerdrError.disconnected
                }
                offset += n
            }
        }
    }

    /// Starts the read loop. `onLine` gets each frame without its newline.
    /// `onClose` fires once, when the peer closes or `close()` is called.
    func startReading(onLine: @escaping @Sendable (Data) -> Void, onClose: @escaping @Sendable () -> Void) {
        let fd = self.fd
        let thread = Thread {
            var pending = Data()
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { break }
                pending.append(contentsOf: chunk[0..<n])
                while let nl = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex..<nl]
                    pending = pending[(nl + 1)...]
                    if !line.isEmpty { onLine(Data(line)) }
                }
            }
            onClose()
        }
        thread.name = "HerdrKit.LineSocket"
        thread.start()
    }

    func close() {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { return }
        closed = true
        shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    deinit { close() }
}
