import Foundation

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LRCParser {
    // Parses "[mm:ss.xx] text" lines (LRCLIB syncedLyrics format).
    static func parse(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\](.*)"#)
        for raw in lrc.components(separatedBy: .newlines) {
            let range = NSRange(raw.startIndex..., in: raw)
            guard let m = regex.firstMatch(in: raw, range: range),
                  let minR = Range(m.range(at: 1), in: raw),
                  let secR = Range(m.range(at: 2), in: raw),
                  let txtR = Range(m.range(at: 3), in: raw),
                  let min = Double(raw[minR]),
                  let sec = Double(raw[secR]) else { continue }
            let text = raw[txtR].trimmingCharacters(in: .whitespaces)
            lines.append(LyricLine(time: min * 60 + sec, text: text))
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
