import SwiftUI
import AVKit

/// The review + mining screen: media on top, the tokenized sentence below with
/// tap-to-select words, and an add-to-pile action. Touch-first port of the
/// desktop ReviewView.
struct ReviewView: View {
    @StateObject private var vm: ReviewViewModel

    init(session: Session) {
        _vm = StateObject(wrappedValue: ReviewViewModel(session: session))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                mediaArea
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .background(Color.black.opacity(0.9))

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        sentenceBlock
                        translationBlock
                        addButton
                    }
                    .padding()
                }

                Divider()
                controls
            }
            .navigationTitle(vm.current.map { "Line \($0.index + 1) / \(vm.session.cues.count)" } ?? "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        PileView(vm: vm)
                    } label: {
                        Label("Pile (\(vm.session.picks.count))", systemImage: "tray.full")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var mediaArea: some View {
        let videoURL = Storage.videoURL(vm.session.id, ext: vm.session.videoExt)
        if FileManager.default.fileExists(atPath: videoURL.path) {
            VideoPlayer(player: AVPlayer(url: videoURL))
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
    }

    private var sentenceBlock: some View {
        FlowLayout(hSpacing: 2, vSpacing: 12) {
            ForEach(Array(vm.tokens.enumerated()), id: \.offset) { pair in
                tokenView(index: pair.offset, token: pair.element)
            }
        }
    }

    @ViewBuilder
    private func tokenView(index: Int, token: RefinedToken) -> some View {
        if token.content {
            let picked = vm.pickedLemmasForCurrent.contains(token.lemma)
            let selected = vm.isSelected(index)
            Button {
                vm.toggle(index)
            } label: {
                Text(token.surface)
                    .font(.system(size: 26, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(picked ? Color.green : Color.accentColor.opacity(0.5))
                            .frame(height: 2)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .foregroundStyle(picked ? Color.green : Color.primary)
        } else {
            Text(token.surface)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var translationBlock: some View {
        if let tr = vm.current?.translation, !tr.isEmpty {
            Text(tr)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var addButton: some View {
        Button {
            vm.commitPicks()
        } label: {
            Label(
                vm.selectedCount == 0 ? "Tap words to add" : "Add \(vm.selectedCount) to pile",
                systemImage: "plus.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(vm.selectedCount == 0)
    }

    private var controls: some View {
        HStack {
            Button { vm.prev() } label: {
                Image(systemName: "chevron.left").frame(maxWidth: .infinity)
            }
            .disabled(!vm.canPrev)

            Button { vm.next() } label: {
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
