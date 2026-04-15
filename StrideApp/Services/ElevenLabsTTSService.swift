import Foundation
import AVFoundation
import CryptoKit
import os.log

private let ttsLog = Logger(subsystem: "com.stride.app", category: "ElevenLabsTTS")

/// Represents a single audio clip in a playback sequence.
enum AudioClip {
    /// Play a pre-recorded MP3 from the app bundle (e.g., "km_5" for Audio/km_5.mp3).
    /// If the bundled file is missing, falls back to API with the provided fallback text.
    case bundled(String, fallbackText: String? = nil)
    /// Dynamic text — check disk cache first, then call ElevenLabs API
    case text(String)
}

/// ElevenLabs Text-to-Speech service with three-tier playback:
/// 1. Bundled audio (pre-recorded, zero latency, zero cost)
/// 2. Disk-cached audio (previously fetched, zero latency after first call)
/// 3. Live API call (first occurrence of dynamic text only)
///
/// Sequences are preloaded into memory before playback starts,
/// eliminating gaps between clips.
final class ElevenLabsTTSService: NSObject, AVAudioPlayerDelegate {
    /// App-wide shared instance so the audio session state has a single owner.
    /// Multiple views creating their own TTS instances caused dangling AVAudioPlayers
    /// whose delegate callbacks never fired — leaving music permanently ducked.
    static let shared = ElevenLabsTTSService()

    private let apiKey = "sk_6c250411f6eed3dafe6b56c013dd12e26160505c379286af"

    /// ElevenLabs voice ID — swap this to change voices.
    var voiceId: String = "fDeOZu1sNd7qahm2fV4k"

    /// Model to use. "eleven_multilingual_v2" for quality, "eleven_flash_v2_5" for speed.
    private let modelId = "eleven_flash_v2_5"

    private var audioPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?  // Pre-prepared for gapless transition
    private var overlapTimer: Timer?
    /// Queue of preloaded audio data ready for instant playback
    private var preloadedQueue: [Data] = []
    private var isSpeaking = false
    private var audioSessionConfigured = false
    /// Pending deactivation scheduled after the queue drains. Cancelled if a new
    /// sequence arrives within the debounce window so we don't flap the session.
    private var deactivationWorkItem: DispatchWorkItem?
    private let deactivationDebounce: TimeInterval = 0.4
    /// How early (in seconds) to start the next clip before current finishes.
    /// This trims the trailing silence baked into each MP3 clip.
    private let overlapAmount: TimeInterval = 0.12

    /// Disk cache directory for dynamically fetched audio
    private lazy var cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("VoiceCoach", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override init() {
        super.init()
    }

    // MARK: - Audio Session

    /// Activate ducking just before speech starts. Music dips while we talk.
    private func activateDucking() {
        // If a deactivation was queued from a prior sequence, cancel it — we're speaking again.
        deactivationWorkItem?.cancel()
        deactivationWorkItem = nil
        guard !audioSessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true, options: [])
            audioSessionConfigured = true
        } catch {
            ttsLog.error("Audio session activation failed: \(error.localizedDescription)")
        }
    }

    /// Schedule deactivation after a short debounce so back-to-back sequences don't flap
    /// the session. When it runs, iOS receives the notifyOthersOnDeactivation signal
    /// that tells music apps to restore full volume.
    private func scheduleDeactivation() {
        deactivationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Bail if another clip started during the debounce window.
            if self.isSpeaking || !self.preloadedQueue.isEmpty { return }
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                self.audioSessionConfigured = false
            } catch {
                ttsLog.error("Audio session deactivation failed: \(error.localizedDescription)")
            }
        }
        deactivationWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + deactivationDebounce, execute: item)
    }

    /// Immediate deactivation for stopSpeaking() where we know the user cancelled.
    private func deactivateImmediately() {
        deactivationWorkItem?.cancel()
        deactivationWorkItem = nil
        guard audioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            audioSessionConfigured = false
        } catch {
            ttsLog.error("Audio session deactivation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public API

    /// Speak a single text string (with disk cache).
    func speak(_ text: String) {
        speakSequence([.text(text)])
    }

    /// Play a sequence of audio clips in order.
    /// All clips are preloaded into memory first, then played back-to-back with no gaps.
    /// `onStart` fires the instant the first clip actually begins audible playback.
    /// `onComplete` fires on the main queue once the last clip's audio has played out
    /// (or immediately if no clips resolved).
    func speakSequence(_ clips: [AudioClip], onStart: (() -> Void)? = nil, onComplete: (() -> Void)? = nil) {
        guard !clips.isEmpty else { onComplete?(); return }
        print("[ElevenLabs] Preloading sequence: \(clips.count) clips")

        Task {
            // Resolve all clips to Data on a background thread
            var audioDataList: [Data] = []

            for clip in clips {
                if let data = await resolveClip(clip) {
                    audioDataList.append(data)
                }
            }

            guard !audioDataList.isEmpty else {
                await MainActor.run { onComplete?() }
                return
            }

            await MainActor.run {
                print("[ElevenLabs] Preloaded \(audioDataList.count) clips, starting playback")
                // Chain completion handlers if another sequence is already pending.
                if let existing = self.sequenceCompletion, let next = onComplete {
                    self.sequenceCompletion = { existing(); next() }
                } else {
                    self.sequenceCompletion = onComplete ?? self.sequenceCompletion
                }
                // onStart fires on the first audible play only (ignored if already speaking).
                self.pendingOnStart = onStart ?? self.pendingOnStart
                preloadedQueue.append(contentsOf: audioDataList)
                playNextPreloaded()
            }
        }
    }

    /// Resolve the given text to audio data and write it to the disk cache without
    /// playing. Used to pre-warm the cache so a later speakSequence call plays instantly.
    func prefetchText(_ text: String) async {
        _ = await resolveTextClip(text)
    }

    /// Fires once when the next batch of audio actually begins playing.
    private var pendingOnStart: (() -> Void)?

    /// Fires once the playback queue has fully drained.
    private var sequenceCompletion: (() -> Void)?

    /// Play a single bundled audio file.
    func playBundled(_ name: String) {
        speakSequence([.bundled(name)])
    }

    func stopSpeaking() {
        overlapTimer?.invalidate()
        overlapTimer = nil
        preloadedQueue.removeAll()
        audioPlayer?.stop()
        audioPlayer = nil
        nextPlayer = nil
        isSpeaking = false
        deactivateImmediately()
    }

    // MARK: - Clip Resolution (preload to Data)

    /// Resolve a clip to audio Data — bundled from disk, cached from disk, or fetched from API.
    private func resolveClip(_ clip: AudioClip) async -> Data? {
        switch clip {
        case .bundled(let name, fallbackText: let fallbackText):
            return await resolveBundledClip(name, fallbackText: fallbackText)
        case .text(let text):
            return await resolveTextClip(text)
        }
    }

    private func resolveBundledClip(_ name: String, fallbackText: String?) async -> Data? {
        // Try bundled file
        if let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
           let data = try? Data(contentsOf: url) {
            print("[ElevenLabs] Preloaded bundled: \(name).mp3")
            return data
        }

        // Fall back to API
        if let text = fallbackText {
            ttsLog.warning("Bundled clip missing: \(name).mp3 — falling back to API")
            print("[ElevenLabs] FALLBACK: \(name).mp3 missing, resolving via API: \"\(text)\"")
            return await resolveTextClip(text)
        }

        ttsLog.error("Bundled clip not found and no fallback: \(name).mp3")
        print("[ElevenLabs] ERROR: Bundled clip not found: \(name).mp3 (no fallback)")
        return nil
    }

    private func resolveTextClip(_ text: String) async -> Data? {
        let cacheFile = cacheURL(for: text)

        // Check disk cache
        if let data = try? Data(contentsOf: cacheFile) {
            print("[ElevenLabs] Cache hit: \"\(text)\"")
            return data
        }

        // Fetch from API
        print("[ElevenLabs] Cache miss, fetching: \"\(text)\"")
        do {
            let audioData = try await fetchSpeech(text: text)
            print("[ElevenLabs] Got audio: \(audioData.count) bytes")

            // Log API character usage
            await MainActor.run {
                TTSUsageLog.shared.logCharacters(text.count)
            }

            // Cache to disk
            try? audioData.write(to: cacheFile)
            ttsLog.debug("Cached: \(cacheFile.lastPathComponent)")

            return audioData
        } catch {
            print("[ElevenLabs] ERROR: \(error)")
            ttsLog.error("TTS failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Preloaded Playback

    private func playNextPreloaded() {
        guard !isSpeaking else { return }
        guard !preloadedQueue.isEmpty else {
            if audioSessionConfigured { scheduleDeactivation() }
            // Fire completion now that the queue has fully drained.
            if let done = sequenceCompletion {
                sequenceCompletion = nil
                done()
            }
            return
        }

        activateDucking()

        let data = preloadedQueue.removeFirst()
        let wasFirstClipOfBatch = !isSpeaking
        isSpeaking = true

        do {
            // If we already pre-prepared this player, use it instantly
            if let ready = nextPlayer {
                audioPlayer = ready
                nextPlayer = nil
                audioPlayer?.delegate = self
                audioPlayer?.play()
            } else {
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.delegate = self
                audioPlayer?.volume = 1.0
                audioPlayer?.play()
            }

            // Fire onStart the moment the first clip in a batch begins playing.
            if wasFirstClipOfBatch, let start = pendingOnStart {
                pendingOnStart = nil
                start()
            }

            // Pre-prepare the NEXT player while this one plays
            prepareNextPlayer()

            // Schedule overlap: start next clip slightly before this one ends
            // This trims the trailing silence from each MP3
            scheduleOverlap()
        } catch {
            ttsLog.error("Audio playback failed: \(error.localizedDescription)")
            isSpeaking = false
            playNextPreloaded()
        }
    }

    /// Schedule the next clip to start slightly before the current clip's trailing silence.
    private func scheduleOverlap() {
        overlapTimer?.invalidate()
        guard let player = audioPlayer, !preloadedQueue.isEmpty, nextPlayer != nil else { return }

        let triggerTime = max(0, player.duration - overlapAmount)
        overlapTimer = Timer.scheduledTimer(withTimeInterval: triggerTime, repeats: false) { [weak self] _ in
            guard let self, self.isSpeaking else { return }
            self.overlapTimer = nil

            // Stop current clip and immediately start the pre-prepared next one
            self.audioPlayer?.stop()
            self.isSpeaking = false
            self.advanceToNextPlayer()
        }
    }

    /// Instantly start the pre-prepared next player.
    private func advanceToNextPlayer() {
        guard let ready = nextPlayer, !preloadedQueue.isEmpty else {
            playNextPreloaded()
            return
        }

        preloadedQueue.removeFirst()
        isSpeaking = true
        audioPlayer = ready
        nextPlayer = nil
        audioPlayer?.delegate = self
        audioPlayer?.play()

        prepareNextPlayer()
        scheduleOverlap()
    }

    /// Pre-create the next AVAudioPlayer so it starts instantly when the current clip finishes.
    private func prepareNextPlayer() {
        guard !preloadedQueue.isEmpty else {
            nextPlayer = nil
            return
        }

        do {
            nextPlayer = try AVAudioPlayer(data: preloadedQueue[0])
            nextPlayer?.volume = 1.0
            nextPlayer?.prepareToPlay()  // Pre-buffers audio for instant start
        } catch {
            nextPlayer = nil
        }
    }

    // MARK: - Cache Helpers

    private func cacheURL(for text: String) -> URL {
        let hash = SHA256.hash(data: Data(text.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(hashString).mp3")
    }

    /// Returns the total size of cached audio files in bytes.
    func cacheSize() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }

    /// Clears all cached audio files.
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        ttsLog.info("Voice cache cleared")
    }

    // MARK: - ElevenLabs API

    private func fetchSpeech(text: String) async throws -> Data {
        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": 0.35,
                "similarity_boost": 0.8,
                "style": 0.3,
                "use_speaker_boost": true
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[ElevenLabs] API error \(httpResponse.statusCode): \(errorBody)")
            throw TTSError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        return data
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        overlapTimer?.invalidate()
        overlapTimer = nil
        isSpeaking = false
        advanceToNextPlayer()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        ttsLog.error("Audio decode error: \(error?.localizedDescription ?? "unknown")")
        isSpeaking = false
        playNextPreloaded()
    }

    // MARK: - Errors

    enum TTSError: Error {
        case invalidResponse
        case apiError(statusCode: Int, message: String)
    }
}
