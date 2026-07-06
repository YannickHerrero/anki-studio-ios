import SwiftUI

/// Yomitan-style dictionary popup: long-press a token in review to open it.
struct DictionarySheet: View {
    let token: RefinedToken

    @State private var entries: [DictionaryService.Entry] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if !loaded {
                    ProgressView()
                } else if entries.isEmpty {
                    ContentUnavailableView(
                        "No entry",
                        systemImage: "character.book.closed.ja",
                        description: Text("「\(token.lemma)」 isn't in the dictionary.")
                    )
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.kanji.isEmpty ? entry.kana : entry.kanji)
                                    .font(.title3.weight(.semibold))
                                if !entry.kanji.isEmpty {
                                    Text(entry.kana)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if entry.isCommon {
                                    Text("common")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }
                            ForEach(entry.senses) { sense in
                                VStack(alignment: .leading, spacing: 1) {
                                    if !sense.partOfSpeech.isEmpty {
                                        Text(sense.partOfSpeech)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(sense.id + 1). \(sense.gloss)")
                                        .font(.callout)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(token.surface)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                entries = await DictionaryService.shared.lookup(
                    lemma: token.lemma, surface: token.surface)
                loaded = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
