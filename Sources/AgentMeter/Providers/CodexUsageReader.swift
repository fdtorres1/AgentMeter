import Foundation

/// Reads Codex/ChatGPT rate-limit usage from the Codex CLI session logs.
///
/// Every Codex CLI response appends a `token_count` event containing a
/// `rate_limits` snapshot to the active rollout file under
/// `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. We locate the most recently
/// modified session files and scan them backwards for the newest snapshot.
struct CodexUsageReader {
    var sessionsRoot: URL

    init(sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")) {
        self.sessionsRoot = sessionsRoot
    }

    func readUsage() throws -> ProviderUsage {
        let files = recentSessionFiles(limit: 25)
        guard !files.isEmpty else {
            throw CodexReadError.noSessions
        }
        for file in files {
            if let usage = try? Self.latestRateLimits(inFileAt: file) {
                return usage
            }
        }
        throw CodexReadError.noRateLimitsFound
    }

    /// Session files across the most recent day directories, newest first.
    func recentSessionFiles(limit: Int) -> [URL] {
        let fm = FileManager.default
        var dayDirs: [String] = []
        // Directory names are zero-padded (2026/07/01) so lexical sort == chronological.
        for year in (try? fm.contentsOfDirectory(atPath: sessionsRoot.path))?.sorted(by: >) ?? [] {
            let yearURL = sessionsRoot.appendingPathComponent(year)
            for month in (try? fm.contentsOfDirectory(atPath: yearURL.path))?.sorted(by: >) ?? [] {
                let monthURL = yearURL.appendingPathComponent(month)
                for day in (try? fm.contentsOfDirectory(atPath: monthURL.path))?.sorted(by: >) ?? [] {
                    dayDirs.append(monthURL.appendingPathComponent(day).path)
                    if dayDirs.count >= 5 { break }
                }
                if dayDirs.count >= 5 { break }
            }
            if dayDirs.count >= 5 { break }
        }

        var files: [(url: URL, mtime: Date)] = []
        for dir in dayDirs {
            let dirURL = URL(fileURLWithPath: dir)
            let contents = (try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            for url in contents where url.pathExtension == "jsonl" {
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                files.append((url, mtime))
            }
        }
        return files.sorted { $0.mtime > $1.mtime }.prefix(limit).map(\.url)
    }

    /// Scans a rollout jsonl file backwards for the newest rate_limits snapshot.
    ///
    /// Session files grow to hundreds of MB, and rate-limit events are appended
    /// with every response, so the snapshot we want is near the end. Reading
    /// the file tail in small chunks keeps memory flat regardless of file size.
    static func latestRateLimits(inFileAt url: URL) throws -> ProviderUsage {
        let chunkSize = 256 * 1024
        // Bail out after scanning this much from the end; a file whose last 8 MB
        // has no rate_limits event won't have a newer one than the next file.
        let maxScanBytes: UInt64 = 8 * 1024 * 1024

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()

        var offset = fileSize
        // Bytes of the (possibly partial) line carried over from the previous
        // chunk; prepended to the next chunk read so lines split across chunk
        // boundaries are reassembled.
        var carry = Data()
        let needle = Data("\"rate_limits\"".utf8)
        let newline = UInt8(ascii: "\n")

        while offset > 0, fileSize - offset < maxScanBytes {
            let readSize = min(UInt64(chunkSize), offset)
            offset -= readSize
            try handle.seek(toOffset: offset)
            guard var chunk = try handle.read(upToCount: Int(readSize)) else { break }
            chunk.append(carry)

            var usage: ProviderUsage?
            autoreleasepool {
                var lineEnd = chunk.endIndex
                var searchEnd = chunk.endIndex
                while searchEnd > chunk.startIndex {
                    let lineStart: Data.Index
                    if let nl = chunk[chunk.startIndex..<searchEnd].lastIndex(of: newline) {
                        lineStart = chunk.index(after: nl)
                        searchEnd = nl
                    } else if offset == 0 {
                        lineStart = chunk.startIndex
                        searchEnd = chunk.startIndex
                    } else {
                        // Partial line at chunk start; defer to the next iteration.
                        carry = chunk[chunk.startIndex..<lineEnd]
                        return
                    }
                    let lineData = chunk[lineStart..<lineEnd]
                    lineEnd = searchEnd
                    guard lineData.range(of: needle) != nil,
                          let line = String(data: lineData, encoding: .utf8) else { continue }
                    if let parsed = parse(line: line) {
                        usage = parsed
                        return
                    }
                }
                carry = Data()
            }
            if let usage { return usage }
        }
        throw CodexReadError.noRateLimitsFound
    }

    static func parse(line: String) -> ProviderUsage? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = findRateLimits(in: object) else {
            return nil
        }

        var windows: [UsageWindow] = []
        if let primary = rateLimits["primary"] as? [String: Any],
           let window = window(from: primary) {
            windows.append(window)
        }
        if let secondary = rateLimits["secondary"] as? [String: Any],
           let window = window(from: secondary) {
            windows.append(window)
        }
        guard !windows.isEmpty else { return nil }

        var asOf: Date?
        if let timestamp = object["timestamp"] as? String {
            asOf = ISO8601DateFormatter.flexible.date(from: timestamp)
                ?? ISO8601DateFormatter.plain.date(from: timestamp)
        }
        let plan = rateLimits["plan_type"] as? String
        return ProviderUsage(planName: plan?.capitalized, windows: windows, asOf: asOf)
    }

    private static func window(from dict: [String: Any]) -> UsageWindow? {
        guard let usedPercent = dict["used_percent"] as? Double else { return nil }
        let minutes = dict["window_minutes"] as? Int ?? 0
        var resetsAt: Date?
        if let epoch = dict["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: epoch)
        }
        return UsageWindow(
            label: Self.windowLabel(minutes: minutes),
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 0: return "Window"
        case ..<120: return "\(minutes)m limit"
        case ..<2880: return "\(minutes / 60)h limit"
        default:
            let days = minutes / 1440
            return days == 7 ? "Weekly limit" : "\(days)d limit"
        }
    }

    /// Recursively searches a decoded JSON object for a "rate_limits" dictionary.
    private static func findRateLimits(in object: [String: Any]) -> [String: Any]? {
        if let hit = object["rate_limits"] as? [String: Any] { return hit }
        for value in object.values {
            if let nested = value as? [String: Any], let hit = findRateLimits(in: nested) {
                return hit
            }
        }
        return nil
    }
}

enum CodexReadError: LocalizedError {
    case noSessions
    case noRateLimitsFound
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .noSessions: return "No Codex session logs found"
        case .noRateLimitsFound: return "No rate-limit data in recent sessions"
        case .unreadableFile: return "Could not read session file"
        }
    }
}

extension ISO8601DateFormatter {
    static let flexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
