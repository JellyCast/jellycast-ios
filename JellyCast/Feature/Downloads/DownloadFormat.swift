import UIKit

/// The words for a download's size and progress, shared by the button, the list and the accessory.
enum DownloadFormat {
    static func bytes(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false))
    }

    /// "± 5.7 GB" before the size is known.
    static func estimate(_ bytes: Int64) -> String {
        "± " + Self.bytes(bytes)
    }

    static func kind(_ kind: DownloadKind) -> String {
        switch kind {
        case .compact: String(localized: "Compact · 1080p")
        case .original: String(localized: "Original")
        }
    }

    /// "Compact · 1080p · ± 1.1 GB", or the final size once done.
    static func sizeLine(_ download: Download) -> String {
        let size: String? = switch download.status {
        case .done: bytes(download.bytes)
        default: download.totalBytes.map(bytes) ?? download.estimatedBytes.map(estimate)
        }
        return Format.joined([kind(download.kind), size])
    }

    /// "Converting on the server · 42% · about 4 min left", "Waiting in line", …
    static func statusLine(_ download: Download, secondsLeft: Double?) -> String {
        let percent = download.fraction.map { "\(Int(($0 * 100).rounded(.down)))%" }
        switch download.status {
        case .queued:
            return String(localized: "Waiting in line")
        case .running:
            let action = download.kind == .compact
                ? String(localized: "Converting on the server") : String(localized: "Downloading")
            return Format.joined([action, percent, secondsLeft.map(timeLeft)])
        case .waitingForNetwork:
            return String(localized: "Waiting for the network")
        case .paused:
            return Format.joined([String(localized: "Paused"), percent])
        case .failed(let message):
            return String(localized: "Didn't finish: \(message)")
        case .done:
            return String(localized: "On this \(UIDevice.current.localizedModel)")
        }
    }

    static func timeLeft(_ seconds: Double) -> String {
        let minutes = max(Int((seconds / 60).rounded(.up)), 1)
        return String(localized: "about \(minutes) min left")
    }
}
