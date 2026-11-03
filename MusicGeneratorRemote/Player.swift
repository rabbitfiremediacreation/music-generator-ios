import AVFoundation
import MediaPlayer
import Observation

/// Spielt Songs vom Mac per Streaming, auch im Hintergrund und mit Steuerung auf dem Sperrbildschirm.
@MainActor @Observable
final class Player {
    private(set) var current: Song?
    private(set) var isPlaying = false
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var error: String?

    private var queue: [Song] = []
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    /// Lautstärke der App (0…1), unabhängig von den Lautstärketasten; bleibt gespeichert.
    var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 1 {
        didSet {
            player.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }

    init() {
        // longFormAudio: Musik-App, AirPlay 2 auf Lautsprecher im Netzwerk
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
        player.volume = Float(volume)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        setupRemoteCommands()
    }

    /// Spielt `song` und merkt sich die Liste für Weiter/Zurück.
    func play(_ song: Song, in list: [Song]) {
        queue = list.filter(\.isPlayable)
        // Aufs iPhone geladene Songs spielen von dort, auch ohne Verbindung zum Mac
        let local = Downloads.shared.localURL(song)
        guard let url = local ?? (try? APIClient.current.audioURL(song)) else { return }
        current = song
        error = nil
        position = 0
        duration = song.duration ?? 0
        let asset = local != nil ? AVURLAsset(url: url)
            : AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": APIClient.current.headers])
        let item = AVPlayerItem(asset: asset)
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            let message = item.status == .failed ? (item.error?.localizedDescription ?? "Wiedergabe fehlgeschlagen") : nil
            Task { @MainActor in if let message { self?.error = message; self?.isPlaying = false } }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
        player.replaceCurrentItem(with: item)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    /// Übernimmt eine geänderte Fassung (Favorit, Ordner), ohne die Wiedergabe anzufassen.
    func refresh(_ song: Song) {
        if current?.id == song.id { current = song }
        if let i = queue.firstIndex(where: { $0.id == song.id }) { queue[i] = song }
    }

    func toggle() {
        guard current != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
        updateNowPlaying()
    }

    func next() { step(1) }
    func previous() {
        if position > 3 { seek(to: 0) } else { step(-1) }
    }

    private func step(_ delta: Int) {
        guard let current, let i = queue.firstIndex(where: { $0.id == current.id }) else { return }
        let j = i + delta
        if queue.indices.contains(j) { play(queue[j], in: queue) } else { player.pause(); isPlaying = false; updateNowPlaying() }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        position = seconds
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
    }

    private func setupRemoteCommands() {
        // Die Befehle kommen auf dem Hauptthread an.
        let c = MPRemoteCommandCenter.shared()
        func on(_ cmd: MPRemoteCommand, _ action: @escaping @MainActor (Player) -> Void) {
            cmd.addTarget { [weak self] _ in
                MainActor.assumeIsolated { if let self { action(self) } }
                return .success
            }
        }
        on(c.playCommand) { $0.resumeIfPaused() }
        on(c.pauseCommand) { $0.pauseIfPlaying() }
        on(c.togglePlayPauseCommand) { $0.toggle() }
        on(c.nextTrackCommand) { $0.next() }
        on(c.previousTrackCommand) { $0.previous() }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func resumeIfPaused() { if !isPlaying { toggle() } }
    private func pauseIfPlaying() { if isPlaying { toggle() } }

    private func updateNowPlaying() {
        guard let current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: current.displayTitle,
            MPMediaItemPropertyArtist: "Music Generator",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }
}
