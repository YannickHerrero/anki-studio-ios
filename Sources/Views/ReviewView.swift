import SwiftUI
import AVKit
import UIKit

/// The review + mining screen: media on top, the tokenized sentence below with
/// tap-to-select words, and an add-to-pile action. Touch-first port of the
/// desktop ReviewView.
struct ReviewView: View {
    @StateObject private var vm: ReviewViewModel
    @StateObject private var segmentPlayer = SegmentPlayer()
    @State private var clipPlayer: AVAudioPlayer?
    @State private var dictionaryToken: RefinedToken?
    @State private var showsExplain = false

    init(session: Session) {
        let vm = ReviewViewModel(session: session)
        // Debug/screenshot hook: jump straight to a given cue index.
        if let raw = ProcessInfo.processInfo.environment["REVIEW_INDEX"],
           let i = Int(raw), session.cues.indices.contains(i) {
            vm.index = i
        }
        _vm = StateObject(wrappedValue: vm)
    }

    private var videoURL: URL? {
        let url = Storage.videoURL(vm.session.id, ext: vm.session.videoExt)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Play the current cue: video segment when the video is present,
    /// otherwise the pre-cut audio clip.
    private func playCurrent() {
        guard let cue = vm.current else { return }
        if let videoURL {
            segmentPlayer.load(videoURL)
            segmentPlayer.playSegment(startMs: cue.startMs, endMs: cue.endMs)
        } else {
            let clip = Storage.audioURL(vm.session.id, cue.index)
            clipPlayer = try? AVAudioPlayer(contentsOf: clip)
            clipPlayer?.play()
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The content mirrors the Anki card: one floating panel on the
                // warm paper background — media as the card's top section
                // (like the card screenshot, hairline under it, audio pill
                // overlaid), then the rule-labelled sections.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        mediaArea
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .background(Theme.videoBg)
                            .clipped()

                        Rectangle()
                            .fill(Theme.line)
                            .frame(height: 1)

                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 14) {
                                RuleLabel(text: "Context")
                                sentenceBlock
                                    .frame(maxWidth: .infinity)
                            }

                            if let tr = vm.current?.translation, !tr.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    RuleLabel(text: "Meaning")
                                    Text(tr)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.ink)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.panelInset, in: RoundedRectangle(cornerRadius: 6))
                            }

                            addButton
                        }
                        .padding(18)
                    }
                    .background(Theme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
                    .padding(16)
                }
                .background(Theme.page)

                // Pre-iOS 26 fallback: on 26+ the prev/next controls live in
                // the tab bar's Liquid Glass accessory instead.
                if #unavailable(iOS 26.1) {
                    Divider().overlay(Theme.line)
                    controls
                        .background(Theme.page)
                }
            }
            .navigationTitle(vm.current.map { "Line \($0.index + 1) / \(vm.session.cues.count)" } ?? "Review")
            .navigationBarTitleDisplayMode(.inline)
            // The media now lives inside the card, so the bar sits on paper.
            .toolbarBackground(Theme.page, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                ReviewNav.shared.active = vm
                playCurrent()
            }
            .onDisappear {
                if ReviewNav.shared.active === vm { ReviewNav.shared.active = nil }
                segmentPlayer.stop()
                clipPlayer?.stop()
            }
            .onChange(of: vm.index) { playCurrent() }
            .sheet(item: $dictionaryToken) { token in
                DictionarySheet(token: token)
            }
            .toolbar {
                // Explain this line (interlinear gloss) — desktop's Explain tab.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap()
                        showsExplain = true
                    } label: {
                        Label("Explain", systemImage: "text.bubble")
                    }
                    .disabled(vm.current == nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        PileView(vm: vm)
                    } label: {
                        Label("Pile (\(vm.session.picks.count))", systemImage: "tray.full")
                    }
                }
            }
            .sheet(isPresented: $showsExplain) {
                if let cue = vm.current {
                    ExplainSheet(cue: cue) { gloss in
                        vm.setGloss(gloss, forCueIndex: cue.index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaArea: some View {
        ZStack(alignment: .bottomLeading) {
            if videoURL != nil {
                VideoPlayer(player: segmentPlayer.player)
            } else if let cue = vm.current,
                      let image = UIImage(contentsOfFile: Storage.screenshotURL(vm.session.id, cue.index).path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.5))
                    if let cue = vm.current {
                        Text(timeLabel(cue))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            // Replay the cue's segment (Space on desktop).
            Button {
                Haptics.tap()
                playCurrent()
            } label: {
                // The card's green play disc (.js-audio--overlay).
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white, Theme.accent)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var sentenceBlock: some View {
        if vm.tokens.isEmpty {
            // No tokenization for this cue — show the plain sentence rather
            // than nothing (desktop behavior).
            Text(vm.current?.text ?? "")
                .font(Theme.jp(24, .medium))
                .foregroundStyle(Theme.ink)
        } else {
            FlowLayout(hSpacing: 2, vSpacing: 14) {
                ForEach(Array(vm.tokens.enumerated()), id: \.offset) { pair in
                    tokenView(index: pair.offset, token: pair.element)
                }
            }
        }
    }

    @ViewBuilder
    private func tokenView(index: Int, token: RefinedToken) -> some View {
        if token.content {
            let picked = vm.pickedLemmasForCurrent.contains(token.lemma)
            let selected = vm.isSelected(index)
            Text(token.surface)
                .font(Theme.jp(24, .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(selected ? Theme.accent.opacity(0.18) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(picked ? Theme.accent : Theme.accent.opacity(0.4))
                        .frame(height: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(picked ? Theme.accent : Theme.ink)
                .contentShape(Rectangle())
                // Tap = yomitan-style lookup; long-press = toggle in the
                // multi-select (committed by the add-to-pile button).
                .onTapGesture {
                    Haptics.tap()
                    dictionaryToken = token
                }
                .onLongPressGesture {
                    Haptics.select()
                    vm.toggle(index)
                }
        } else {
            Text(token.surface)
                .font(Theme.jp(24))
                .foregroundStyle(Theme.muted)
        }
    }

    private var addButton: some View {
        Button {
            Haptics.success()
            vm.commitPicks()
        } label: {
            Label(
                vm.selectedCount == 0 ? "Hold words to select" : "Add \(vm.selectedCount) to pile",
                systemImage: "plus.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.accent)
        .disabled(vm.selectedCount == 0)
    }

    private var controls: some View {
        HStack {
            Button {
                Haptics.tap()
                vm.prev()
            } label: {
                Image(systemName: "chevron.left").frame(maxWidth: .infinity)
            }
            .disabled(!vm.canPrev)

            Button {
                Haptics.tap()
                vm.next()
            } label: {
                Image(systemName: "chevron.right").frame(maxWidth: .infinity)
            }
            .disabled(!vm.canNext)
        }
        .font(.title2)
        .padding(.vertical, 10)
    }

    private func timeLabel(_ cue: Cue) -> String {
        func fmt(_ ms: Int) -> String {
            let s = ms / 1000
            return String(format: "%02d:%02d", s / 60, s % 60)
        }
        return "\(fmt(cue.startMs)) – \(fmt(cue.endMs))"
    }
}
