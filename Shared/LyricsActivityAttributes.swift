import ActivityKit
import Foundation

struct LyricsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentLine: String
        var nextLine: String
        var trackName: String
        var artistName: String
        var isPlaying: Bool
    }
}
