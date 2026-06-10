import ActivityKit
import Foundation

// Coordinator: polls Spotify, fetches lyrics on track change,
// computes the current line from playback position, drives the Live Activity.
@MainActor
final class LyricsEngine: ObservableObject {
    @Published var track: CurrentTrack?
    @Published var lines: [LyricLine] = []
    @Published var currentIndex: Int = -1
    @Published var errorMessage: String?

    private let auth: SpotifyAuth
    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private let activity = LiveActivityManager()
    private var lastTrackId: String?
    private var lastIsPlaying: Bool?
    private var lastActivityPushAt: Date?
    private var fetchingId: String?
    private var attemptedId: String?  // one lyrics attempt per track, no refetch spam
    private var linesTrackId: String? // which track `lines` belongs to

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func start() {
        guard pollTask == nil else { return }
        if !activity.activitiesEnabled {
            errorMessage = "Live Activity disattivate: Impostazioni → Dynamic Lyrics → Attività in tempo reale"
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        // Async loop instead of a run-loop Timer: keeps ticking while the
        // screen is locked (audio keep-alive holds the process alive).
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        // Recover automatically if the user flips the Live Activity toggle.
        authTask = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard let self else { return }
                if enabled {
                    if self.errorMessage?.contains("Live Activity") == true { self.errorMessage = nil }
                } else {
                    self.errorMessage = "Live Activity disattivate: Impostazioni → Dynamic Lyrics → Attività in tempo reale"
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        tickTask?.cancel(); tickTask = nil
        authTask?.cancel(); authTask = nil
        activity.end()
    }

    // Playback position extrapolated between polls, clamped to track length.
    private var positionSeconds: TimeInterval {
        guard let t = track else { return 0 }
        var pos = TimeInterval(t.progressMs) / 1000
        if t.isPlaying { pos += Date().timeIntervalSince(t.fetchedAt) }
        if t.durationMs > 0 { pos = min(pos, Double(t.durationMs) / 1000) }
        return pos
    }

    private func poll() async {
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 204 || data.isEmpty { // nothing playing (Spotify may send empty 200)
                track = nil
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Spotify HTTP \(http.statusCode)"
                return
            }

            // Lenient decode: every field optional so a missing/unexpected
            // field (local files with null id, podcasts, ads) never freezes state.
            struct Playing: Decodable {
                struct Item: Decodable {
                    struct Artist: Decodable { let name: String? }
                    struct Album: Decodable { let name: String? }
                    let id: String?
                    let name: String?
                    let artists: [Artist]?
                    let album: Album?
                    let duration_ms: Int?
                }
                let item: Item?
                let progress_ms: Int?
                let is_playing: Bool?
            }
            let playing = try JSONDecoder().decode(Playing.self, from: data)
            guard let item = playing.item, (item.name ?? "").isEmpty == false else { return }

            let name = item.name ?? "—"
            let artist = (item.artists ?? []).compactMap(\.name).joined(separator: ", ")
            // Stable identity: real id, or name+artist+duration for items without one.
            let trackKey = item.id ?? "local|\(name)|\(artist)|\(item.duration_ms ?? 0)"

            let previousKey = track?.id
            let newTrack = CurrentTrack(
                id: trackKey,
                name: name,
                artist: artist,
                album: item.album?.name ?? "",
                durationMs: item.duration_ms ?? 0,
                progressMs: playing.progress_ms ?? 0,
                isPlaying: playing.is_playing ?? false,
                fetchedAt: Date()
            )
            track = newTrack
            errorMessage = nil

            if trackKey != previousKey {
                lines = []
                currentIndex = -1
                linesTrackId = nil
                attemptedId = nil
            }
            // One non-blocking lyrics attempt per track: the poll cadence must
            // never wait on the lyrics fetch, or position extrapolation drifts.
            if lines.isEmpty, fetchingId != trackKey, attemptedId != trackKey {
                fetchingId = trackKey
                attemptedId = trackKey
                Task { [weak self] in
                    let fetched = await LyricsService.fetch(track: newTrack)
                    guard let self else { return }
                    // Discard if the user already moved to another song meanwhile.
                    if self.track?.id == trackKey {
                        self.lines = fetched
                        self.currentIndex = -1
                        self.linesTrackId = trackKey
                    }
                    if self.fetchingId == trackKey { self.fetchingId = nil }
                }
            }
            tick()
        } catch {
            errorMessage = "Spotify: \(error.localizedDescription)"
        }
    }

    private func tick() {
        guard let t = track else {
            activity.end()
            lastTrackId = nil
            lastIsPlaying = nil
            return
        }
        let pos = positionSeconds
        // Never show lines that belong to another track (race between
        // track change and the async lyrics fetch).
        let lyricsReady = linesTrackId == t.id
        let newIndex = lyricsReady ? (lines.lastIndex(where: { $0.time <= pos }) ?? -1) : -1
        let trackChanged = t.id != lastTrackId
        let playStateChanged = t.isPlaying != lastIsPlaying
        // Heartbeat keeps the Live Activity fresh through long instrumental gaps.
        let heartbeat = lastActivityPushAt.map { Date().timeIntervalSince($0) >= 20 } ?? true
        guard trackChanged || playStateChanged || activity.needsStart || heartbeat
                || (lyricsReady && newIndex != currentIndex) else {
            return
        }
        currentIndex = newIndex
        lastTrackId = t.id
        lastIsPlaying = t.isPlaying
        let current: String
        if !lyricsReady {
            current = "♪" // neutral while the right lyrics load
        } else if newIndex >= 0 {
            let text = lines[newIndex].text
            current = text.isEmpty ? "♪" : text
        } else {
            current = lines.isEmpty ? "♪ Nessun testo trovato" : "♪"
        }
        let next = (lyricsReady && newIndex + 1 < lines.count) ? lines[newIndex + 1].text : ""
        activity.update(currentLine: current, nextLine: next, track: t)
        lastActivityPushAt = Date()
        if let laErr = activity.lastError { errorMessage = laErr }
    }
}
