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

## Status

Work in progress; built milestone by milestone. See the module layout
under `Sources/`.
