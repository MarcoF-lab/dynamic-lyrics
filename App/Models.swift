import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    // Parses LRC lines, including condensed multi-timestamp lines
    // ("[00:10.00][00:20.00] text") and comma decimal separators.
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let tagRegex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.,]\d+)?)\]"#)
        for raw in lrc.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            let matches = tagRegex.matches(in: raw, range: range)
            guard let last = matches.last,
                  let textRange = Range(NSRange(location: last.range.upperBound,
                                                length: range.length - last.range.upperBound),
                                        in: raw) else { continue }
            let text = raw[textRange].trimmingCharacters(in: .whitespaces)
            for m in matches {
                guard let minR = Range(m.range(at: 1), in: raw),
                      let secR = Range(m.range(at: 2), in: raw),
                      let mins = Double(raw[minR]),
                      let secs = Double(raw[secR].replacingOccurrences(of: ",", with: ".")) else { continue }
                lines.append(LyricLine(time: mins * 60 + secs, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}

struct CurrentTrack: Equatable {
    let id: String
    let name: String
    let artist: String
    let album: String
    let durationMs: Int
    let progressMs: Int
    let isPlaying: Bool
    let fetchedAt: Date
}
