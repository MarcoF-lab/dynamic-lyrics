import AVFoundation
import Foundation

// Plays a silent loop so iOS keeps the app alive in background
// (UIBackgroundModes: audio). Mixes with Spotify without ducking it.
final class KeepAlive {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?

    var isActive: Bool { player?.isPlaying ?? false }

    func start() {
        guard player == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let p = try AVAudioPlayer(data: Self.silentWav(seconds: 2))
            p.numberOfLoops = -1
            p.volume = 0
            p.play()
            player = p
        } catch {
            print("KeepAlive failed: \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Minimal PCM WAV of silence, generated in memory — no asset file needed.
    private static func silentWav(seconds: Int) -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(seconds) * sampleRate * 2 // 16-bit mono
        var d = Data()
        func append(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: "RIFF".utf8); append(36 + dataSize)
        d.append(contentsOf: "WAVE".utf8)
        d.append(contentsOf: "fmt ".utf8); append(16)
        append16(1); append16(1)            // PCM, mono
        append(sampleRate); append(sampleRate * 2)
        append16(2); append16(16)           // block align, bits
        d.append(contentsOf: "data".utf8); append(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }
}
