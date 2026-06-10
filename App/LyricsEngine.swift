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
    private var tickTimer: Timer?
    private let activity = LiveActivityManager()
    private var lastTrackId: String?
    private var fetchingId: String?

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tickTimer?.invalidate()
        tickTimer = nil
        activity.end()
    }

    // Playback position extrapolated between polls.
    private var positionSeconds: TimeInterval {
        guard let t = track else { return 0 }
        var pos = TimeInterval(t.progressMs) / 1000
        if t.isPlaying { pos += Date().timeIntervalSince(t.fetchedAt) }
        return pos
    }

    private func poll() async {
        do {
            let token = try await auth.validAccessToken()
            var req = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 204 { // nothing playing
                track = nil
                return
            }
            guard http.statusCode == 200 else { return }

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
            // Stable identity: real id, or name+artist for items without one.
            let trackKey = item.id ?? "\(name)|\(artist)"

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
            }
            // Fetch lyrics for the current track if we don't have them yet
            // and we're not already fetching this exact track.
            if lines.isEmpty, fetchingId != trackKey {
                fetchingId = trackKey
                let fetched = await LyricsService.fetch(track: newTrack)
                // Discard if the user already moved to another song meanwhile.
                if track?.id == trackKey {
                    lines = fetched
                    currentIndex = -1
                }
                fetchingId = nil
            }
        } catch {
            errorMessage = "Spotify: \(error.localizedDescription)"
        }
    }

    private func tick() {
        guard let t = track else {
            activity.end()
            lastTrackId = nil
            return
        }
        let pos = positionSeconds
        let newIndex = lines.lastIndex(where: { $0.time <= pos }) ?? -1
        let trackChanged = t.id != lastTrackId
        guard trackChanged || newIndex != currentIndex || activity.needsStart else {
            return
        }
        currentIndex = newIndex
        lastTrackId = t.id
        let current = newIndex >= 0 ? lines[newIndex].text : (lines.isEmpty ? "♪ Nessun testo trovato" : "♪")
        let next = newIndex + 1 < lines.count ? lines[newIndex + 1].text : ""
        activity.update(
            currentLine: current.isEmpty ? "♪" : current,
            nextLine: next,
            track: t
        )
        if let laErr = activity.lastError { errorMessage = laErr }
    }
}
