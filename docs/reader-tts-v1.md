# Reader TTS V1

Reader TTS is an Apple-layer feature. It consumes only the final
`ChapterContentResult.content` returned by the existing content runtime and cache; raw HTTP,
HTML, selector intermediates, and character-set decoding are outside the speech boundary.

## Architecture

- `ReaderSpeechController` is created once by `AppDependencies`. It owns the active speech
  session, speech cursor, sleep task, Audio Session, remote commands, and Now Playing state.
- `ReaderSpeechSynthesizing` hides `AVSpeechSynthesizer`. The production adapter is
  `@MainActor`; tests use a fake and never produce audio.
- `ReaderViewModel` remains the chapter owner. Speech-driven chapter changes call its existing
  cache-first switch/load path, including request identity checks, adjacent preload, pagination,
  and progress persistence. TTS does not implement another content loader.
- Leaving the Reader does not stop an active session. The app-level controller retains the
  active Reader model until playback stops and rebinds when the same book is reopened. Starting
  speech in another book first stops the previous session.

## Text and progress semantics

`ReaderSpeechSegmenter` uses Foundation sentence enumeration, preserves source order, ignores
whitespace-only results, and splits unexpectedly long sentences near a natural boundary. All
ranges are stable UTF-16 offsets and split boundaries are expanded to composed-character
sequences, so emoji and other grapheme clusters are not cut in the middle.

Playback starts from the segment containing the current normalized reading offset, or the first
segment after it. A segment offset maps back to `ReadingProgress.chapterProgress` by dividing its
UTF-16 offset by the final content UTF-16 length. Progress writes continue through the Reader's
existing debounce and are flushed on pause, stop, interruption, and chapter boundaries.

Paged mode finds the `ReaderPage.utf16Range` containing the speech offset and directly assigns
the page index; this intentionally bypasses cover-turn animation. Scroll mode updates shared
normalized progress but does not force a scroll for every sentence. Chapter transitions still
restore the new chapter at its start.

## Platform behavior

The production Audio Session uses `.playback` with `.spokenAudio`, enabling speech with the mute
switch and under the `audio` background mode. Calls/Siri interruptions and removal of an old audio
route pause playback and require an explicit user resume. Deactivation uses
`.notifyOthersOnDeactivation`.

Remote play, pause, toggle, next, and previous commands are registered once at app composition.
Next/previous mean next/previous sentence. Now Playing contains only book and chapter names; no
fake duration or remote cover download is used.

Rate choices are user-facing multipliers and are mapped around
`AVSpeechUtteranceDefaultSpeechRate` within Apple's supported minimum/maximum range. A saved voice
identifier is validated against installed voices; missing voices fall back to the current
`zh-CN` system voice without hard-coding a device-specific identifier.

Persistent speech preferences are rate, voice identifier, and continuous reading. Sleep timer
selection is session-only and resets to off on launch. Timed options use one cancellable task;
"本章结束" overrides continuous reading only at the next chapter boundary and never changes the
persistent continuous-reading preference.

## V1 limitations

- Scroll mode does not force the viewport to each spoken sentence.
- Speech uses one selected/default voice per session and does not perform per-sentence language
  detection.
- Interruption recovery is intentionally manual.
- Now Playing does not expose a fabricated duration or elapsed time.
