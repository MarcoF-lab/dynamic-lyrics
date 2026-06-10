import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var activity: Activity<LyricsActivityAttributes>?

    var needsStart: Bool { activity == nil }

    func update(currentLine: String, nextLine: String, track: CurrentTrack) {
        let state = LyricsActivityAttributes.ContentState(
            currentLine: currentLine,
            nextLine: nextLine,
            trackName: track.name,
            artistName: track.artist,
            isPlaying: track.isPlaying
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(30))
        if let activity {
            Task { await activity.update(content) }
        } else {
            activity = try? Activity.request(
                attributes: LyricsActivityAttributes(),
                content: content
            )
        }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
