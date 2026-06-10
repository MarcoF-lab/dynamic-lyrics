import Foundation

// Synced lyrics from lrclib.net — free, no API key.
enum LyricsService {
    struct LRCLIBResponse: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double? // seconds, present on /api/search results
    }

    static func fetch(track: CurrentTrack) async -> [LyricLine] {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            .init(name: "artist_name", value: track.artist),
            .init(name: "track_name", value: track.name),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(track.durationMs / 1000)),
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("DynamicLyricsClone/1.0", forHTTPHeaderField: "User-Agent")
        if let lines = await request(req), !lines.isEmpty { return lines }

        // Fallback search: pick the result whose duration matches this track,
        // never blindly the first one (a remix must not get the original's timing).
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            .init(name: "artist_name", value: track.artist),
            .init(name: "track_name", value: track.name),
        ]
        var sreq = URLRequest(url: search.url!)
        sreq.setValue("DynamicLyricsClone/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: sreq),
              let results = try? JSONDecoder().decode([LRCLIBResponse].self, from: data) else { return [] }
        let target = Double(track.durationMs) / 1000
        let best = results
            .filter { $0.syncedLyrics != nil && $0.duration != nil }
            .min { abs($0.duration! - target) < abs($1.duration! - target) }
        guard let candidate = best, let dur = candidate.duration, abs(dur - target) <= 3,
              let synced = candidate.syncedLyrics else { return [] }
        return LRCParser.parse(synced)
    }

    private static func request(_ req: URLRequest) async -> [LyricLine]? {
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(LRCLIBResponse.self, from: data),
              let synced = decoded.syncedLyrics else { return nil }
        return LRCParser.parse(synced)
    }
}
