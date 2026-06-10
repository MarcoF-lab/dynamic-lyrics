import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var activity: Activity<LyricsActivityAttributes>?
    private(set) var lastError: String?

    var needsStart: Bool { activity == nil }
    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func update(currentLine: String, nextLine: String, track: CurrentTrack) {
        guard activitiesEnabled else {
            lastError = "Live Activity disattivate: Impostazioni → Dynamic Lyrics → Attività in tempo reale"
            return
        }
        let state = LyricsActivityAttributes.ContentState(
            currentLine: currentLine,
            nextLine: nextLine,
            trackName: track.name,
            artistName: track.artist,
            isPlaying: track.isPlaying
        )
        // staleDate nil: content stays fresh until our next push — a long
        // instrumental gap must not dim or kill the activity.
        let content = ActivityContent(state: state, staleDate: nil,
                                      relevanceScore: track.isPlaying ? 100 : 50)
        if let activity {
            Task { await activity.update(content) }
        } else {
            do {
                activity = try Activity.request(
                    attributes: LyricsActivityAttributes(),
                    content: content
                )
                lastError = nil
            } catch {
                lastError = "LA: \(error.localizedDescription)"
            }
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
