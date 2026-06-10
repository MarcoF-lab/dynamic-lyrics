import SwiftUI

@main
struct DynamicLyricsApp: App {
    @StateObject private var auth: SpotifyAuth
    @StateObject private var engine: LyricsEngine

    init() {
        let auth = SpotifyAuth()
        _auth = StateObject(wrappedValue: auth)
        _engine = StateObject(wrappedValue: LyricsEngine(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
