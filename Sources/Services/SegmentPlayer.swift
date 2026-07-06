import Foundation
import AVFoundation

/// Plays the current cue's segment of the session video: seeks to the cue
/// start, plays, and pauses at the cue end. Port of the desktop ReviewView's
/// playVideoSegment / onVideoTimeupdate pair.
@MainActor
final class SegmentPlayer: ObservableObject {
    let player = AVPlayer()

    private var timeObserver: Any?
    private var endSeconds: Double = .infinity

    init() {
        // Play through the ringer/silent switch like any media app.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        // Stop at the cue's end so playback stays within the line's window.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if CMTimeGetSeconds(time) >= self.endSeconds {
                    self.player.pause()
                }
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    /// Point the player at a video file (no-op if already loaded).
    func load(_ url: URL) {
        let current = (player.currentItem?.asset as? AVURLAsset)?.url
        guard current != url else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    /// Seek to the cue and play just its window (plus a touch of lead-out).
    func playSegment(startMs: Int, endMs: Int) {
        endSeconds = Double(endMs) / 1000
        let start = CMTime(value: CMTimeValue(startMs), timescale: 1000)
        player.pause()
        player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in self?.player.play() }
        }
    }

    func stop() {
        player.pause()
    }
}
