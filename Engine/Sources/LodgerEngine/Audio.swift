import AVFoundation
import Foundation

/// Sound playback.
///
/// Off unless the host turns it on: an always-running background app that makes
/// noise unprompted is the fastest route to being uninstalled.
///
/// **Per-frame sounds cost timers, and that is unavoidable.** Sprite frames are
/// advanced by the render server, so the app does not know when one appears without
/// asking - and asking every frame is the poll Rule 2 forbids. So a clip's frame
/// sounds are *scheduled* when the clip is installed: one wake per sound, not one
/// per frame, and only while audio is enabled and the clip actually has any. A clip
/// with no `sound` on any frame schedules nothing. State-level sounds fire once on
/// entry and cost nothing at all.
public final class Audio {

    public var enabled = false { didSet { if !enabled { stopAll() } } }
    public var volume: Double = 0.4

    private var players: [String: [AVAudioPlayer]] = [:]
    private var root: URL?
    private var sounds: [String: Pack.Sound] = [:]
    private var timers: [DispatchSourceTimer] = []

    public private(set) var scheduledCount = 0
    public var liveTimers: Int { timers.count }

    public init() {}
    deinit { stopAll() }

    public func load(pack: Pack, root: URL) {
        stopAll()
        self.root = root
        self.sounds = pack.sounds
        players.removeAll()
    }

    /// Play one sound now. Safe to call when disabled or when the id is unknown.
    public func play(_ id: String) {
        guard enabled, let sound = sounds[id], let root else { return }
        let url = root.appendingPathComponent(sound.file)
        let pool = players[id] ?? []
        let free = pool.first { !$0.isPlaying }
        let player: AVAudioPlayer
        if let free {
            player = free
        } else {
            guard pool.count < max(1, sound.maxConcurrent),
                  let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.prepareToPlay()
            players[id, default: []].append(p)
            player = p
        }
        player.volume = Float(volume * (sound.volume ?? 0.5))
        player.currentTime = 0
        player.play()
    }

    /// Schedule a clip's per-frame sounds across one pass of the clip.
    ///
    /// Returns the number of wakes scheduled, so the caller can report it. Scheduling
    /// nothing is the common case.
    @discardableResult
    public func schedule(clip: Pack.Clip, defaultFrameMs: Int, loop: Bool) -> Int {
        cancelScheduled()
        guard enabled else { return 0 }
        let ms = clip.durations(default: defaultFrameMs)
        let total = ms.reduce(0, +)
        guard total > 0 else { return 0 }

        var at = 0
        var offsets: [(TimeInterval, String)] = []
        for (i, frame) in clip.frames.enumerated() {
            if let s = frame.sound { offsets.append((Double(at) / 1000, s)) }
            at += ms[i]
        }
        guard !offsets.isEmpty else { return 0 }

        for (delay, id) in offsets {
            let t = DispatchSource.makeTimerSource(queue: .main)
            if loop {
                t.schedule(deadline: .now() + delay,
                           repeating: .milliseconds(total),
                           leeway: .milliseconds(20))
            } else {
                t.schedule(deadline: .now() + delay, leeway: .milliseconds(20))
            }
            t.setEventHandler { [weak self] in self?.play(id) }
            timers.append(t)
            t.resume()
        }
        scheduledCount += offsets.count
        return offsets.count
    }

    public func cancelScheduled() {
        for t in timers { t.cancel() }
        timers.removeAll()
    }

    public func stopAll() {
        cancelScheduled()
        for pool in players.values { for p in pool where p.isPlaying { p.stop() } }
    }
}
