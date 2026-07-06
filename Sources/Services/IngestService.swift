import Foundation

/// One observable run of the YouTube ingest pipeline. Mirrors the desktop
/// client's phase sequence (YouTubeView.vue): probe → download → extract
/// audio → transcribe → translate → tokenize → cut per-cue media → ready.
///
/// The flow has two halves: `prepare(urlString:)` does the quick probe and
/// the subtitles-vs-Whisper question while the Add sheet is on screen, then
/// `start(_:settings:)` runs the long pipeline — on iOS 26 inside a
/// BGContinuedProcessingTask so it survives backgrounding, with the system
/// Live Activity showing phase + progress.
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

    /// Everything decided up-front so the long pipeline never needs input.
    struct Prepared {
        let urlString: String
        let probe: YouTubeService.Probe
        let subsTrack: CaptionsService.Track?
    }

    @Published var phase: Phase = .idle
    @Published var progress: Double? // 0…1 within the current phase, when known
    @Published var detail: String = ""
    @Published var errorMessage: String?
    /// Non-nil while prepare() waits for the user to pick uploader subtitles
    /// vs Whisper (the desktop's pre-ingest modal).
    @Published var showsSubsChoice = false

    private var subsContinuation: CheckedContinuation<Bool, Never>?
    private var pipelineTask: Task<Void, Never>?
    /// The session being built, so failures can mark it on disk.
    private var currentSessionID: String?

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

    // MARK: - Subs choice

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

    // MARK: - Prepare (foreground, quick)

    /// Probe the video and settle the subtitles question while the sheet is
    /// still on screen, so the long pipeline never blocks on user input.
    func prepare(urlString: String) async -> Prepared? {
        errorMessage = nil
        setPhase(.probing)
        do {
            let probe = try await YouTubeService.probe(urlString: urlString)
            let tracks = (try? await CaptionsService.listTracks(videoID: probe.videoID)) ?? []
            var subsTrack = CaptionsService.manualJapanese(in: tracks)
            if subsTrack != nil {
                let useSubs = await awaitSubsChoice()
                if !useSubs { subsTrack = nil }
            }
            return Prepared(urlString: urlString, probe: probe, subsTrack: subsTrack)
        } catch {
            fail(error)
            return nil
        }
    }

    // MARK: - Start (long pipeline, background-capable)

    func start(_ prepared: Prepared, settings: AppSettings) {
        let work: @MainActor () async -> Void = { [weak self] in
            await self?.pipeline(prepared, settings: settings)
        }

        if #available(iOS 26.1, *) {
            let submitted = BackgroundImporter.begin(
                title: "Importing \(prepared.probe.title)",
                work: work,
                onExpiration: { [weak self] in self?.handleExpiration() })
            if submitted { return }
            // Scheduler refused (e.g. simulator) — run in-process instead.
        }
        pipelineTask = Task { await work() }
    }

    /// The system expired the continued-processing task (or the user hit
    /// cancel on the Live Activity).
    private func handleExpiration() {
        pipelineTask?.cancel()
        errorMessage = "Import stopped in the background — start it again to finish."
        setPhase(.failed)
    }

    // MARK: - Pipeline

    private func pipeline(_ prepared: Prepared, settings: AppSettings) async {
        do {
            var session = Session(
                source: .youtube, title: prepared.probe.title, youtubeURL: prepared.urlString)
            session.status = .processing
            try Storage.ensureSessionDirs(session.id)
            session = try store.save(session)
            currentSessionID = session.id

            // 1. Download the progressive mp4.          (overall 0.00 → 0.35)
            setPhase(.downloading, base: 0.00, span: 0.35)
            let videoURL = Storage.videoURL(session.id, ext: session.videoExt)
            try await YouTubeService.download(prepared.probe, to: videoURL) { p in
                Task { @MainActor [weak self] in
                    if self?.phase == .downloading { self?.setInner(p) }
                }
            }
            try Task.checkCancellation()
            session.videoDurationMs = try await MediaService.durationMs(of: videoURL)
            session = try store.save(session)

            // 2. Cues: uploader subtitles or Whisper.   (overall 0.35 → 0.55)
            if let subsTrack = prepared.subsTrack {
                setPhase(.fetchingSubs, base: 0.35, span: 0.20)
                session.cues = try await CaptionsService.fetchCues(track: subsTrack)
            } else {
                setPhase(.extractingAudio, base: 0.35, span: 0.07)
                let fullAudio = Storage.fullAudioURL(session.id)
                try await MediaService.extractFullAudio(video: videoURL, to: fullAudio)
                try Task.checkCancellation()

                setPhase(.transcribing, base: 0.42, span: 0.13)
                let transcript = try await WhisperService.transcribe(
                    audio: fullAudio, apiKey: settings.openaiKey.trimmed)
                guard !transcript.cues.isEmpty else { throw WhisperError.empty }
                session.cues = transcript.cues
            }
            try Task.checkCancellation()
            session = try store.save(session)

            let llm = OpenRouterService.Options(
                apiKey: settings.openrouterKey.trimmed, model: settings.model)

            // 3. Translate the whole transcript.        (overall 0.55 → 0.75)
            setPhase(.translating, base: 0.55, span: 0.20)
            let translations = try await OpenRouterService.translateBatch(
                session.cues.map(\.text), opts: llm
            ) { done, total in
                Task { @MainActor [weak self] in
                    if self?.phase == .translating {
                        self?.setInner(Double(done) / Double(max(total, 1)))
                        self?.detail = "\(done)/\(total) lines"
                    }
                }
            }
            for i in session.cues.indices where i < translations.count {
                if !translations[i].isEmpty { session.cues[i].translation = translations[i] }
            }
            session = try store.save(session)

            // 4. Tokenize: LLM primary, local fallback. (overall 0.75 → 0.90)
            setPhase(.tokenizing, base: 0.75, span: 0.15)
            let batchSize = 20
            var start = 0
            while start < session.cues.count {
                try Task.checkCancellation()
                let end = min(start + batchSize, session.cues.count)
                let local = session.cues[start..<end].map {
                    (cueIndex: $0.index, sentence: $0.text, hint: TokenizerService.tokenize($0.text))
                }
                let refined = (try? await OpenRouterService.refineTokenBatch(local, opts: llm)) ?? [:]
                for (offset, i) in (start..<end).enumerated() {
                    session.cues[i].refinedTokens =
                        refined[session.cues[i].index] ?? local[offset].hint
                }
                start = end
                setInner(Double(start) / Double(session.cues.count))
                detail = "\(start)/\(session.cues.count) lines"
                session = try store.save(session)
            }

            // 5. Per-cue audio clips + screenshots.     (overall 0.90 → 1.00)
            setPhase(.cuttingMedia, base: 0.90, span: 0.10)
            let processed = await MediaService.processCues(session: session) { done, total in
                Task { @MainActor [weak self] in
                    if self?.phase == .cuttingMedia {
                        self?.setInner(Double(done) / Double(max(total, 1)))
                        self?.detail = "\(done)/\(total) cues"
                    }
                }
            }
            try Task.checkCancellation()
            session.cues = processed
            session.status = .ready
            session = try store.save(session)

            setPhase(.done, base: 1.0, span: 0)
            progress = 1
            currentSessionID = nil
        } catch is CancellationError {
            // handleExpiration already surfaced the state.
            markSessionErrored("Import was interrupted.")
        } catch {
            fail(error)
        }
    }

    /// Flip the on-disk session to error so it doesn't sit "processing"
    /// forever — the Library then shows it failed and it can be deleted.
    private func markSessionErrored(_ message: String) {
        guard let sid = currentSessionID, var session = store.session(sid) else { return }
        session.status = .error
        session.errorMessage = message
        try? store.save(session)
        currentSessionID = nil
    }

    // MARK: - Progress plumbing

    private var phaseBase: Double = 0
    private var phaseSpan: Double = 0

    private func setPhase(_ p: Phase, base: Double = 0, span: Double = 0) {
        phase = p
        phaseBase = base
        phaseSpan = span
        progress = span > 0 ? 0 : nil
        detail = ""
        reportOverall()
    }

    /// Progress within the current phase (0…1).
    private func setInner(_ inner: Double) {
        progress = inner
        reportOverall()
    }

    private func reportOverall() {
        if #available(iOS 26.1, *) {
            let overall = min(1, phaseBase + phaseSpan * (progress ?? 0))
            BackgroundImporter.report(overall: overall, phase: phase.rawValue)
        }
    }

    private func fail(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        setPhase(.failed)
        markSessionErrored(errorMessage ?? "Import failed.")
    }
}
