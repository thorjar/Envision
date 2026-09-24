import Foundation

// Port of lib/subtitles.ts: WebVTT/SRT parsing and cue lookup.

struct SubtitleCue {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

private func subtitleTimestamp(_ value: String) -> TimeInterval? {
    let parts = value.replacingOccurrences(of: ",", with: ".")
        .split(separator: ":").compactMap { Double($0) }
    guard (2...3).contains(parts.count) else { return nil }
    return parts.reduce(0) { $0 * 60 + $1 }
}

/// Parse a WebVTT (or SRT-compatible) document into cues.
func parseWebVtt(_ source: String) -> [SubtitleCue] {
    let text = source
        .replacingOccurrences(of: "\u{FEFF}", with: "")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    var cues: [SubtitleCue] = []
    for block in text.components(separatedBy: "\n\n") {
        let lines = block.components(separatedBy: "\n")
        guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
        let halves = lines[timingIndex].components(separatedBy: "-->")
        guard halves.count == 2,
              let start = subtitleTimestamp(halves[0].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)[0]),
              let end = subtitleTimestamp(halves[1].trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)[0]),
              end > start else { continue }
        var body = lines[(timingIndex + 1)...].joined(separator: "\n")
        // Strip basic markup and entities like the web implementation.
        while let range = body.range(of: "<[^>]*>", options: .regularExpression) {
            body.removeSubrange(range)
        }
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            body = body.replacingOccurrences(of: entity, with: replacement)
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            cues.append(SubtitleCue(start: start, end: end, text: trimmed))
        }
    }
    return cues
}

/// The cue text visible at a given playback time.
func visibleSubtitle(_ cues: [SubtitleCue], at time: TimeInterval) -> String {
    cues.filter { $0.start <= time && time < $0.end }
        .map(\.text)
        .joined(separator: "\n")
}

/// Convert an SRT document (or validate a VTT one) into WebVTT text.
func toWebVtt(_ source: String, fileName: String) throws -> String {
    let text = source
        .replacingOccurrences(of: "\u{FEFF}", with: "")
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let trimmed = text.drop(while: { $0.isWhitespace })
    let lower = fileName.lowercased()
    if lower.hasSuffix(".vtt") || trimmed.hasPrefix("WEBVTT") {
        guard trimmed.hasPrefix("WEBVTT") else {
            throw APIError.failed(0, "This VTT file is invalid.")
        }
        return text
    }
    guard lower.hasSuffix(".srt") else {
        throw APIError.failed(0, "Import an SRT or VTT subtitle file.")
    }
    let converted = text.components(separatedBy: "\n")
        .map { $0.contains(" --> ") ? $0.replacingOccurrences(of: ",", with: ".") : $0 }
        .joined(separator: "\n")
    let vtt = "WEBVTT\n\n\(converted)"
    guard !parseWebVtt(vtt).isEmpty else {
        throw APIError.failed(0, "This subtitle file contains no readable cues.")
    }
    return vtt
}
