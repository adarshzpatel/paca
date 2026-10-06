import Foundation

/// Stderr trace for scripted runs. Enable with PACA_DEBUG=1.
let debugEnabled = ProcessInfo.processInfo.environment["PACA_DEBUG"] == "1"

func debugLog(_ message: @autoclosure () -> String) {
    guard debugEnabled else { return }
    FileHandle.standardError.write(Data("[paca] \(message())\n".utf8))
}

/// PACA_DEBUG=1: logs every main-thread stall over 12 ms (the cause of input and scroll lag).
enum MainThreadWatchdog {
    private static var timer: DispatchSourceTimer?
    private static var activity: NSObjectProtocol?

    static func start() {
        guard debugEnabled, timer == nil else { return }
        // Scripted runs sit in the background, where App Nap delays the main queue and makes
        // every measurement look like a stall. Opt out so numbers match a frontmost app.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                         reason: "PACA_DEBUG measurements")
        let queue = DispatchQueue(label: "paca.watchdog")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(10))
        timer.setEventHandler {
            let sent = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                let lag = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                if lag > 12 { debugLog(String(format: "main stall %.0fms", lag)) }
            }
        }
        timer.resume()
        self.timer = timer
    }
}
