# Guitar Learn App: Plan and Feature List

A free play-along guitar app for school kids and adults who can't read music. The screen shows a full-size guitar neck with 6 strings, and the app lights up exactly where to press and which string to play, in time with the song, like the old MIDI player programs. The app also plays the guitar sound itself, generated live from the same notes shown on screen (no pre-recorded audio). You watch, listen and play along on your real guitar.

Runs on Android phones, tablets and Android TV from one codebase. Languages: English and Serbian.

## 1. Decisions so far

| Topic | Decision |
|---|---|
| Platforms | Android phone, Android tablet, Android TV. No iOS for now. |
| Price | Free. No ads, no accounts required. |
| Audience | School kids and adults with no music knowledge. |
| Languages | English and Serbian at launch. |
| Songs | Start with public-domain songs. New songs can be added later and published to a server, and the app downloads them over the Internet. |
| Main screen | A full-screen guitar neck with 6 strings where finger presses and plucked strings are easy to see. |
| Audio | The app plays guitar sound generated live from the notes on screen, like a MIDI file played through a synthesizer. No pre-recorded audio. |

## 2. How it works for the player

1. Open the app and search or browse songs (big cards, easy words).
2. Tap a song, then choose **Easy** (chords only) or **Full** (every note).
3. Press **Play**. A 3-2-1 countdown appears, then the neck view starts:
   - A **colored dot** appears on the fret where a finger should press, with the finger number (1 = index ... 4 = pinky).
   - The **string to play glows and vibrates** at the exact moment it should be plucked.
   - For strums, a **sweep arrow** runs across the strings (down or up).
   - The **next notes fade in** a moment before they are due, so the player has time to move their fingers.
4. **Pause, slow down, loop.** A big slider sets the speed from 25% to 100%. A section can be looped. "Wait mode" stops at each note until the player taps "next" (helpful for kids).

## 3. Feature list

### MVP (first release)

| Area | Feature |
|---|---|
| **Neck view (main feature)** | Full-screen landscape fretboard: 6 strings, frets 0 to 12, fret markers, open-string and muted-string symbols, large finger dots with numbers and colors |
| | String glow/vibrate animation when a string should be played; strum sweep arrows |
| | Next-note preview (dots fade in before they are due) |
| | Left-handed mode (mirror) and a "flip strings" option (thin string on top like written tabs, or thick string on top as you see your own guitar when looking down) |
| | Optional note names on dots (C, D, E...) and optional chord name at the top |
| **Playback engine** | Plays timed note events like a MIDI sequencer: play, pause, seek, speed 25% to 100%, loop section, wait mode |
| **Sound** | Guitar sound synthesized live from the same notes on screen, so sound and picture always match, at any speed |
| | Sound controls: volume, mute, "play the song for me" (listen first) and "I play, app accompanies" (app plays only chords or bass) |
| | Metronome click (optional) plus a visual beat indicator (flashing dot per beat) |
| | Tap any fret on the neck to hear that note (free-play mode) |
| **Song library** | Search by title or artist in both languages; filters for difficulty and language; lists for "Beginner", "Kids", "Serbian folk" |
| | Bundled starter set of public-domain songs that works offline |
| **Online songs** | App downloads the song catalog from a server over the Internet and caches songs for offline use; new songs appear without an app update |
| **Chord library** | Every chord used in the app shown on the same neck view |
| **Languages** | English and Serbian (Latin script by default; Cyrillic as an option in settings) |
| **Kid friendly** | Big touch targets, icons with short labels, no accounts, no ads, no personal data collected, no chat or user uploads |
| **Android TV** | Same neck view on the big screen, full D-pad navigation, remote play/pause and speed control, listed in the TV launcher |
| **Settings** | Language, left-handed, show note names, colors, speed default |

### Phase 2

- **Song editor / publisher** (web page for you): create songs by tapping notes on a neck, or import a MIDI file, then publish to the server.
- **MIDI import tool**: converts a MIDI melody into string/fret positions automatically (picks the easiest positions), with manual fixes in the editor.
- Guided lessons: "Hold the guitar", "Your first chord", "First 3 chords", with the same neck view.
- Progress (stored on the device only): songs played, stars per song.
- Phone as a remote for the TV app.

### Later

- Microphone check that the right note or chord was played (green/red feedback).
- More languages.
- Ukulele mode (4 strings, same engine).
- Licensed popular songs if a budget appears later.
- iOS version (Flutter makes this possible from the same code).

## 4. Tech stack

**App: Flutter (Dart)**

- One codebase for Android phone, tablet and TV (iOS possible later without a rewrite).
- The neck view is drawn with Flutter's `CustomPainter` on a canvas, which gives smooth 60fps animations for glowing strings and moving dots.
- Android TV: leanback launcher entry in the manifest, focus and D-pad handling with Flutter's `Focus`/`Shortcuts` widgets.
- Languages: Flutter's built-in localization (`flutter_localizations` + ARB files for `en`, `sr_Latn`, `sr_Cyrl`).
- Offline cache: songs stored as JSON files on the device (e.g. with `hive` or plain files).

**Playback engine (MIDI-style sequencer with a built-in synthesizer)**

- A song is a list of timed events (like MIDI): each event says *when* (in beats), *which string*, *which fret*, *which finger* and *how long*.
- A ticker drives the clock at the song's tempo times the speed slider, and the neck view draws whatever events are active or coming up next.
- Each event is also sent to a software synthesizer as a MIDI note (string + fret is converted to pitch using the song's tuning and capo), so the sound always matches the screen, including at slow speeds.
- **Synthesizer (recommended): a SoundFont player.** A small, freely licensed guitar SoundFont (`.sf2`, a few MB, e.g. a nylon or steel acoustic guitar from a permissively licensed set such as GeneralUser GS) played through FluidSynth or a Flutter MIDI package such as `flutter_midi_pro`. Sounds like a real guitar and needs no recordings of songs.
- **Fallback: plucked-string synthesis (Karplus-Strong).** A few dozen lines of code, no sound files at all, sounds like a simple plucked guitar. Good for the first prototype and very old devices.
- Audio latency: schedule notes slightly ahead of time on Android (low-latency audio path via Oboe, used by FluidSynth-based packages) so sound and glowing strings line up.

**Song server (free to run)**

- **Start:** songs live as JSON files in the GitHub repo (`songs/` folder) and are published with GitHub Pages as a static website. The app downloads `songs/index.json` (the catalog) and each song file. Publishing a new song = adding a file to the repo. Free and needs no server maintenance.
- **Later, if needed:** move to Supabase (free tier) for a real database, an admin login, and a web song editor that publishes directly.
- Search runs on the device over the downloaded catalog, which is fast for thousands of songs.

## 5. Song file format (draft)

```json
{
  "id": "ode-to-joy",
  "title": { "en": "Ode to Joy", "sr": "Oda radosti" },
  "artist": "Ludwig van Beethoven",
  "license": "public-domain",
  "language": "instrumental",
  "difficulty": "easy",
  "tempo": 100,
  "timeSignature": [4, 4],
  "tuning": ["E2", "A2", "D3", "G3", "B3", "E4"],
  "capo": 0,
  "tracks": {
    "full": [
      { "beat": 0.0, "string": 1, "fret": 0, "finger": 0, "length": 1 },
      { "beat": 1.0, "string": 1, "fret": 0, "finger": 0, "length": 1 },
      { "beat": 2.0, "string": 1, "fret": 1, "finger": 1, "length": 1 },
      { "beat": 3.0, "string": 1, "fret": 3, "finger": 3, "length": 1 }
    ],
    "easy": [
      { "beat": 0.0, "chord": "C", "strum": "down", "length": 2 },
      { "beat": 2.0, "chord": "G", "strum": "down", "length": 2 }
    ]
  },
  "lyrics": [
    { "beat": 0.0, "text": { "en": "...", "sr": "..." } }
  ]
}
```

Strings are numbered 1 (thin, high E) to 6 (thick, low E), the standard guitar way. A separate `chords.json` holds each chord's finger positions so "easy" tracks can refer to chords by name.

## 6. Starter song list (public domain)

To confirm one by one before adding (melodies are public domain; modern arrangements and lyric translations may not be):

- **Kids:** Twinkle Twinkle Little Star, Old MacDonald, Frère Jacques, Mary Had a Little Lamb, Happy Birthday to You, Row Row Row Your Boat
- **Classics:** Ode to Joy, Greensleeves, Spanish Romance (Romance anónimo), Minuet in G, Für Elise (theme)
- **Folk:** Scarborough Fair, House of the Rising Sun (traditional version), Oh Susanna, Amazing Grace, When the Saints Go Marching In, Auld Lang Syne, Swing Low Sweet Chariot
- **Holidays:** Jingle Bells, Silent Night, We Wish You a Merry Christmas
- **Serbian traditional folk songs:** to be chosen with you; each checked that it is a traditional song with no known modern composer or lyricist.

Good sources of public-domain MIDI and scores: Mutopia Project, IMSLP, and traditional folk collections. Each song file records its source in the `license` field.

## 7. Milestones

| # | Milestone | Outcome |
|---|---|---|
| M0 | Repo, Flutter project, CI build | App runs on a phone emulator and an Android TV emulator |
| M1 | Neck view | Full-screen fretboard with dots, finger numbers, glowing strings, left-handed mode |
| M2 | Playback engine + sound | One hand-made song plays with synthesized guitar sound, countdown, pause, speed and loop |
| M3 | Song format + 10 songs | JSON format finalized, first 10 public-domain songs, chord library |
| M4 | Library + search + languages | Search, filters, English/Serbian UI |
| M5 | Online songs | Catalog and songs downloaded from GitHub Pages and cached offline |
| M6 | Android TV polish | D-pad navigation, large-screen layout, TV launcher |
| M7 | Beta | Internal testing track on Google Play (Families policy checked) |
| M8+ | Phase 2 | Song editor, MIDI import, lessons |

## 8. Repo layout

```
guitar-learn-app/
  README.md
  docs/PLAN.md            (this file)
  app/                    (Flutter app)
  songs/                  (song JSON files, index.json, chords.json, schema)
  tools/                  (MIDI-to-song converter, song validator)
```

## 9. Notes for a kids' app on Google Play

- Declaring children as an audience means following Google Play's **Families policy**: no ads SDKs, no tracking, no personal data. The plan already avoids all of these.
- A short privacy policy page is still required; it can simply say that no data is collected.

## 10. Open questions

- Which Serbian folk songs should be in the first set?
- Default string order: thin string on top (like written tabs and most guitar apps) or thick string on top (as you see your guitar when looking down)? Recommendation: thin on top, with a setting to flip.
