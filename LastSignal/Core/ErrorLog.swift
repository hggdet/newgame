import Foundation
import Combine

// One recorded error, shown on the in-app Arabic error screen.
struct AppErrorInfo: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let file: String
    let line: Int
    let date: Date

    var displayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return """
        إشارة أخيرة — خطأ
        الرسالة: \(message)
        الملف: \(file)
        السطر: \(line)
        الوقت: \(formatter.string(from: date))
        """
    }
}

// Appends errors to Documents/lastsignal-error.log. Never throws to callers:
// a logging failure must never crash the game.
enum ErrorLog {
    static func logFileURL() -> URL? {
        let dirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docs = dirs.first else { return nil }
        return docs.appendingPathComponent("lastsignal-error.log")
    }

    static func write(_ info: AppErrorInfo) {
        guard let url = logFileURL() else { return }
        let text = info.displayText + "\n---\n"
        guard let data = text.data(using: .utf8) else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Silent by design.
        }
    }

    static func readAll() -> String {
        guard let url = logFileURL() else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

// Observable hub: the UI watches `current` and presents ErrorView.
@MainActor
final class ErrorCenter: ObservableObject {
    static let shared = ErrorCenter()

    @Published var current: AppErrorInfo?

    private init() {}

    func report(_ message: String, file: String = #fileID, line: Int = #line) {
        let info = AppErrorInfo(message: message, file: file, line: line, date: Date())
        ErrorLog.write(info)
        current = info
    }

    func dismiss() {
        current = nil
    }
}

// Safe to call from any thread. Never crashes.
func reportError(_ message: String, file: String = #fileID, line: Int = #line) {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            ErrorCenter.shared.report(message, file: file, line: line)
        }
    } else {
        Task { @MainActor in
            ErrorCenter.shared.report(message, file: file, line: line)
        }
    }
}
