import SwiftUI

/// The Explain sheet, "carded" layout (Explain Sheet iOS.html mock): the
/// source sentence, one white card per chunk — green spine, chunk text +
/// reading, a tinted meaning chip, then word rows with dictionary form,
/// English and grammar-tag chips — closed by a tinted MEANING card.
struct ExplainSheet: View {
    let cue: Cue
    let onGenerated: (SentenceGloss) -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var gloss: SentenceGloss?
    @State private var loading = false
    @State private var errorMessage: String?

    init(cue: Cue, onGenerated: @escaping (SentenceGloss) -> Void) {
        self.cue = cue
        self.onGenerated = onGenerated
        _gloss = State(initialValue: cue.gloss)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let gloss {
                    glossView(gloss)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't explain", systemImage: "exclamationmark.bubble")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { generate() }
                    }
                } else {
                    // Also the idle state — the view must render SOMETHING or
                    // SwiftUI never installs it and .task below won't fire.
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Explaining…").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.sheetBg)
            .navigationTitle("Explain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Haptics.tap()
                        generate()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
            .task {
                if gloss == nil { generate() }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func generate() {
        guard !loading else { return }
        guard settings.isConfigured else {
            errorMessage = "Set your OpenRouter key in Settings first."
            return
        }
        loading = true
        errorMessage = nil
        gloss = nil
        Task {
            do {
                let result = try await OpenRouterService.glossSentence(
                    cue.text,
                    opts: .init(apiKey: settings.openrouterKey.trimmed, model: settings.model))
                gloss = result
                onGenerated(result)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            }
            loading = false
        }
    }

    // MARK: - Carded gloss

    private func glossView(_ gloss: SentenceGloss) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Source sentence.
                Text(cue.text)
                    .font(Theme.jp(16, .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)

                ForEach(Array(gloss.chunks.enumerated()), id: \.offset) { _, chunk in
                    ChunkCard(chunk: chunk)
                }

                MeaningCard(
                    full: gloss.naturalTranslation,
                    note: gloss.intent)
                    .padding(.top, 2)
            }
            .padding(16)
        }
    }
}

// MARK: - Chunk card

private struct ChunkCard: View {
    let chunk: GlossChunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: chunk text + reading, then the meaning chip.
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(chunk.phrase)
                        .font(Theme.jp(21, .medium))
                        .foregroundStyle(Theme.ink)
                    if !chunk.reading.isEmpty {
                        Text(chunk.reading)
                            .font(Theme.jp(12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                if !chunk.translation.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("→")
                            .font(.system(size: 12))
                        Text(chunk.translation)
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 11, trailing: 14))

            // Word rows.
            ForEach(Array(chunk.items.enumerated()), id: \.offset) { _, item in
                TokenRow(item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        // The green spine — laid down BEFORE the clip so the rounded corners
        // cut it to the card's curve (the mock's border-left + overflow:hidden).
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Theme.accent)
                .frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

private struct TokenRow: View {
    let item: GlossItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            // Word + reading column.
            VStack(alignment: .leading, spacing: 1) {
                Text(item.token)
                    .font(Theme.jp(15, .medium))
                    .foregroundStyle(Theme.ink)
                if !item.reading.isEmpty, item.reading != item.token {
                    Text(item.reading)
                        .font(Theme.jp(10.5))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(minWidth: 74, alignment: .leading)

            // Dictionary form · meaning · grammar tag.
            FlowLayout(hSpacing: 6, vSpacing: 4) {
                if let base = item.base, !base.isEmpty, base != item.token {
                    Text(base)
                        .font(Theme.jp(12.5))
                        .foregroundStyle(Theme.muted)
                }
                if !item.meaning.isEmpty {
                    Text(item.meaning)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                }
                if let tag = item.tag, !tag.isEmpty {
                    Text(tag)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.2)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .padding(EdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
    }
}

// MARK: - Meaning card

private struct MeaningCard: View {
    let full: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEANING")
                .font(.system(size: 11, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(Theme.accent)
            if !full.isEmpty {
                Text(full)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(2)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 15, bottom: 16, trailing: 15))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.meaningBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.accent.opacity(0.22), lineWidth: 0.5))
    }
}
