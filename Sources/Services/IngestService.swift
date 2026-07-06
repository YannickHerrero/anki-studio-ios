import Foundation

/// One observable run of the YouTube ingest pipeline. Mirrors the desktop
/// client's phase sequence (YouTubeView.vue): probe → download → extract
/// audio → transcribe → translate → tokenize → cut per-cue media → ready.
@MainActor
final class IngestRun: ObservableObject {
    enum Phase: String {
        case idle = "Idle"
        case probing = "Looking up video"
        case awaitingSubsChoice = "Japanese subtitles found"
        case downloading = "Downloading video"
        case fetchingSubs = "Fetching subtitles"
        case extractingAudio = "Extracting audio"
        case transcribing = "Transcribing (Whisper)"
        case translating = "Translating"
        case tokenizing = "Tokenizing"
        case cuttingMedia = "Cutting clips & screenshots"
        case done = "Ready"
        case failed = "Failed"
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double? // 0…1 within the current phase, when known
    @Published var detail: String = ""
    @Published var errorMessage: String?
    /// Non-nil while the pipeline waits for the user to pick uploader
    /// subtitles vs Whisper (the desktop's pre-ingest modal).
    @Published var showsSubsChoice = false

    private var subsContinuation: CheckedContinuation<Bool, Never>?

    /// Resolve the subtitles-vs-Whisper prompt.
    func chooseSubs(useExisting: Bool) {
        showsSubsChoice = false
        subsContinuation?.resume(returning: useExisting)
        subsContinuation = nil
    }

    /// Suspend until the user picks, unless a test hook pre-answers.
    private func awaitSubsChoice() async -> Bool {
        if let forced = ProcessInfo.processInfo.environment["SUBS_CHOICE"] {
            return forced == "subs"
        }
        setPhase(.awaitingSubsChoice)
        return await withCheckedContinuation { cont in
            subsContinuation = cont
            showsSubsChoice = true
        }
    }

    var isRunning: Bool {
        switch phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    private let store: SessionStore

    init(store: SessionStore = .shared) {
        self.store = store
    }

    private func setPhase(_ p: Phase, progress: Double? = nil, detail: String = "") {
        phase = p
        self.progress = progress
        self.detail = detail
    }

    /// Run the full pipeline. Returns the ready session, or nil on failure
    /// (with `errorMessage` set). Partial state is persisted at each step so
    /// a crash never loses completed work.
    @discardableResult
    func run(urlString: String, settings: AppSettings) async -> Session? {
        errorMessage = nil
        do {
            // 1. Probe + create the session.
            setPhase(.probing)
            let probe = try await YouTubeService.probe(urlString: urlString)

            // Uploader-provided Japanese subtitles? Ask before the heavy work,
            // like the desktop's pre-ingest modal. Auto-captions don't count.
            let tracks = (try? await CaptionsService.listTracks(videoID: probe.videoID)) ?? []
            var subsTrack = CaptionsService.manualJapanese(in: tracks)
            if subsTrack != nil {
                let useSubs = await awaitSubsChoice()
                if !useSubs { subsTrack = nil }
            }

            var session = Session(source: .youtube, title: probe.title, youtubeURL: urlString)
            session.status = .processing
            try Storage.ensureSessionDirs(session.id)
            session = try store.save(session)

            // 2. Download the progressive mp4.
            setPhase(.downloading, progress: 0)
            let videoURL = Storage.videoURL(session.id, ext: session.videoExt)
            try await YouTubeService.download(probe, to: videoURL) { p in
                Task { @MainActor [weak self] in
                    if self?.phase == .downloading { self?.progress = p }
                }
            }
            session.videoDurationMs = try await MediaService.durationMs(of: videoURL)
            session = try store.save(session)

            // 3+4. Cues: uploader subtitles when chosen, otherwise Whisper
            //      (extract mono 16k audio → transcribe → sentence split).
            if let subsTrack {
                setPhase(.fetchingSubs)
                session.cues = try await CaptionsService.fetchCues(track: subsTrack)
            } else {
                setPhase(.extractingAudio)
                let fullAudio = Storage.fullAudioURL(session.id)
                try await MediaService.extractFullAudio(video: videoURL, to: fullAudio)

                setPhase(.transcribing)
                let transcript = try await WhisperService.transcribe(
                    audio: fullAudio, apiKey: settings.openaiKey.trimmed)
                guard !transcript.cues.isEmpty else { throw WhisperError.empty }
                session.cues = transcript.cues
            }
            session = try store.save(session)

            let llm = OpenRouterService.Options(
                apiKey: settings.openrouterKey.trimmed, model: settings.model)

            // 5. Translate the whole transcript with context.
            setPhase(.translating, progress: 0)
            let translations = try await OpenRouterService.translateBatch(
                session.cues.map(\.text), opts: llm
            ) { done, total in
                Task { @MainActor [weak self] in
                    if self?.phase == .translating {
                        self?.progress = Double(done) / Double(max(total, 1))
                        self?.detail = "\(done)/\(total) lines"
                    }
                }
            }
            for i in session.cues.indices where i < translations.count {
                if !translations[i].isEmpty { session.cues[i].translation = translations[i] }
            }
            session = try store.save(session)

            // 6. Tokenize: LLM primary (batches of 20), local NL fallback —
            //    same design as desktop (LLM refineTokens over kuromoji).
            setPhase(.tokenizing, progress: 0)
            let batchSize = 20
            var start = 0
            while start < session.cues.count {
                let end = min(start + batchSize, session.cues.count)
                // Local tokenization first: it is the LLM's hint (as kuromoji
                // is on desktop) and the fallback when an entry gets dropped.
                let local = session.cues[start..<end].map {
                    (cueIndex: $0.index, sentence: $0.text, hint: TokenizerService.tokenize($0.text))
                }
                let refined = (try? await OpenRouterService.refineTokenBatch(local, opts: llm)) ?? [:]
                for (offset, i) in (start..<end).enumerated() {
                    session.cues[i].refinedTokens =
                        refined[session.cues[i].index] ?? local[offset].hint
                }
                start = end
                progress = Double(start) / Double(session.cues.count)
                detail = "\(start)/\(session.cues.count) lines"
                session = try store.save(session)
            }

            // 7. Per-cue audio clips + screenshots (concurrency 4).
            setPhase(.cuttingMedia, progress: 0)
            let processed = await MediaService.processCues(session: session) { done, total in
                Task { @MainActor [weak self] in
                    if self?.phase == .cuttingMedia {
                        self?.progress = Double(done) / Double(max(total, 1))
                        self?.detail = "\(done)/\(total) cues"
                    }
                }
            }
            session.cues = processed
            session.status = .ready
            session = try store.save(session)

            setPhase(.done, progress: 1)
            return session
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            setPhase(.failed)
            return nil
        }
    }
}
