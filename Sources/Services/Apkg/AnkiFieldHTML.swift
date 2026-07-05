import Foundation

/// Builds the HTML for the card's rich fields. Ports the relevant helpers from
/// the desktop app (export.ts highlightTargetInSentence, openrouter.ts
/// glossToHtml, and the WordDetails panel).
enum AnkiFieldHTML {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Wrap the first occurrence of the target surface in the sentence with the
    /// `js-target` span so it stands out on the card.
    static func highlightTarget(in sentence: String, target: String) -> String {
        guard !target.isEmpty, let range = sentence.range(of: target) else { return sentence }
        let before = String(sentence[sentence.startIndex..<range.lowerBound])
        let after = String(sentence[range.upperBound...])
        return "\(before)<span class=\"js-target\">\(target)</span>\(after)"
    }

    /// Rendered Word Details panel from the (optional) enriched details.
    static func wordDetails(lemma: String, reading: String, details: WordDetails?) -> String {
        var rows = ["<div class=\"js-word-lemma\">\(escape(lemma))</div>"]

        let meta = [details?.reading ?? reading, details?.partOfSpeech, details?.frequency]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        if !meta.isEmpty {
            let joined = meta.map(escape).joined(separator: " <span class=\"js-word-meta__sep\">·</span> ")
            rows.append("<div class=\"js-word-meta\">\(joined)</div>")
        }
        if let def = details?.definition, !def.isEmpty {
            rows.append("<div class=\"js-word-def\">\(escape(def))</div>")
        }
        if let usage = details?.usageNotes, !usage.isEmpty {
            rows.append("<div class=\"js-word-usage\">\(escape(usage))</div>")
        }
        return "<div class=\"js-word-details\">\(rows.joined())</div>"
    }

    /// Interlinear gloss → HTML. Port of openrouter.ts glossToHtml.
    static func gloss(_ g: SentenceGloss) -> String {
        guard !g.chunks.isEmpty else { return "" }
        let chunks = g.chunks.map { c -> String in
            let reading = c.reading.isEmpty ? "" :
                "<span class=\"js-gloss__reading\">\(escape(c.reading))</span>"
            let items = c.items.map { it -> String in
                let r = it.reading.isEmpty ? "" :
                    " <span class=\"js-gloss__token-reading\">(\(escape(it.reading)))</span>"
                return "<li class=\"js-gloss__item\"><span class=\"js-gloss__token\">\(escape(it.token))</span>\(r) <span class=\"js-gloss__item-gloss\">\(escape(it.gloss))</span></li>"
            }.joined()
            let tr = c.translation.isEmpty ? "" :
                "<div class=\"js-gloss__chunk-tr\">\(escape(c.translation))</div>"
            return "<div class=\"js-gloss__chunk\"><div class=\"js-gloss__phrase\">\(escape(c.phrase))\(reading)</div><ul class=\"js-gloss__items\">\(items)</ul>\(tr)</div>"
        }.joined()
        let natural = g.naturalTranslation.isEmpty ? "" :
            "<div class=\"js-gloss__natural\">\(escape(g.naturalTranslation))</div>"
        let intent = g.intent.isEmpty ? "" :
            "<div class=\"js-gloss__intent\">\(escape(g.intent))</div>"
        return "<div class=\"js-gloss\">\(chunks)\(natural)\(intent)</div>"
    }
}
