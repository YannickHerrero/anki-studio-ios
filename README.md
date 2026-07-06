# Anki Studio iOS

A standalone, on-device Japanese sentence-mining app for iOS. Paste a
YouTube URL → it downloads the video, transcribes it (Whisper), tokenizes
each sentence, and lets you tap words to build Anki cards with audio +
screenshots — then exports a `.apkg` you open directly in AnkiMobile.

Everything runs on the phone. The only network calls are directly to the
user's own cloud AI keys (OpenAI Whisper + OpenRouter). There is no
backend server.

Companion to the desktop [anki-studio](../anki-studio) web app; this port
keeps its spirit while replacing the server pipeline with on-device
equivalents (AVFoundation for media, a Swift YouTube extractor, an
on-device `.apkg` builder).

## Requirements

- Xcode 26+ / iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```sh
xcodegen generate      # regenerate AnkiStudio.xcodeproj from project.yml
open AnkiStudio.xcodeproj
```

The `.xcodeproj` is generated and git-ignored — run `xcodegen` after
cloning or after changing `project.yml`.

## How it works

1. **Add** — paste a YouTube URL. On-device pipeline: YouTubeKit resolves a
   progressive H.264 mp4 (≤480p) → URLSession downloads it → AVFoundation
   extracts mono 16 kHz audio → OpenAI Whisper transcribes with word
   timestamps → sentences are split on punctuation/pauses → OpenRouter
   translates the whole transcript in context and re-tokenizes each line
   (Apple NaturalLanguage as offline fallback) → AVFoundation cuts a padded
   audio clip + midpoint screenshot per line.
2. **Review** — tap words in each sentence to pick them; picked words join
   the pile.
3. **Pile → Export** — builds a `collection.anki2` + legacy-media `.apkg`
   on-device (system SQLite + a built-in zip writer) and hands it to
   AnkiMobile via the share sheet. Note GUIDs are stable, so re-exports
   update instead of duplicating.

Keys (Settings tab) are stored in the Keychain. Requires an OpenAI key
(Whisper) and an OpenRouter key (translation/tokens/gloss).

## Licences & attribution

- This repository bundles a database built from
  [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html)
  (`Resources/dict/jmdict.sqlite`), which is the property of the
  [Electronic Dictionary Research and Development Group](https://www.edrdg.org/)
  and is used in conformance with the Group's
  [licence](https://www.edrdg.org/edrdg/licence.html) (CC BY-SA 4.0).
  Regenerate it with `Scripts/build-jmdict.py`.
- YouTube extraction via [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit).
  Downloading YouTube content may violate YouTube's Terms of Service —
  this app is intended for personal, sideloaded use only.

## Known v1 limits

- Known-words sync from Anki is not ported (AnkiConnect doesn't exist on
  iOS) — every word starts unmarked.
- When the uploader ships manual Japanese subtitles you're asked whether
  to keep them (free, instant) or re-transcribe with Whisper; auto
  captions never count. Subtitle download uses YouTube's InnerTube API
  with a pinned client version that may need occasional bumping.
- Videos offering only VP9/WebM streams are rejected (AVFoundation needs
  H.264 mp4); most videos offer a progressive mp4.
- Long videos are limited by Whisper's 25 MB audio ceiling (~2h at the
  32 kbps mono encode used here); no chunking yet.
