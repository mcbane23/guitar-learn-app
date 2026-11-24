# Guitar Learn App

A free play-along guitar app for school kids and adults who can't read music. A full-screen guitar neck shows where to press and which string to play, and the app plays the guitar sound live from the same notes, with no pre-recorded audio.

- Platforms: Android phone, tablet and Android TV (Flutter)
- Languages: English and Serbian
- Songs: public-domain songs to start, new songs downloaded from the Internet, and your own tab files opened from the device

See [docs/PLAN.md](docs/PLAN.md) for the full plan, feature list and milestones.

## Download a test build

Every push to `main` builds a release APK and publishes it on the [Releases page](../../releases/latest). On the phone, tablet or TV, download the `.apk` file and open it; allow "install from unknown sources" when Android asks. A new build installs as an update over the previous one: the app id is `com.bane23.guitar.learn` and every build (debug and release) is signed with the same debug key (`app/android/app/keystore/debug.keystore`). Builds made before that change used a different id and key, so uninstall that old copy once. The debug key is for testing only; a Play Store release needs its own private key.

## Project layout

```
app/        Flutter app (Android phone, tablet, TV)
songs/      Song files, chords.json and index.json (the online catalog)
tools/      make_songs.py: builds songs/ from short melody descriptions
docs/       Plan and feature list
```

## Working on the app

```
cd app
flutter pub get
flutter test
flutter run            # on a connected device or emulator
```

The guitar sound is synthesized on the device (Karplus-Strong plucked strings, `app/android/.../GuitarSynth.kt`), so there are no audio files.

## Your own songs (tab files)

Tap **Add songs** on the home screen (or in Settings) and pick one or more files from the device. They are read on the device, kept under **My songs** and work offline. Nothing is uploaded, and the app ships no copyrighted music: users bring their own files.

On an Android TV, which usually has no file chooser, choose **Send songs from a phone** instead. The TV shows a QR code and an address such as `http://192.168.1.5:8765/1234`. A phone on the same Wi-Fi scans the code and uploads song files from its browser (`app/lib/share/upload_page.dart`, served by `song_receiver.dart`), or the Guitar Learn app on the phone finds the TV by itself (**Add songs → Send to a TV**, a UDP broadcast on port 8766) and sends files or the whole **My songs** list. The 4-digit code in the address changes every time the screen opens, and the server runs only while that screen is open.

| Format | Extensions | What is used |
|---|---|---|
| Guitar Pro 3, 4, 5 | `.gp3` `.gp4` `.gp5` | strings and frets, tuning, capo, tempo, time signature, repeats, ties, chord names, every guitar track |
| Guitar Pro 6, 7, 8 | `.gpx` `.gp` | the same, from the XML score inside the file |
| MIDI | `.mid` `.midi` `.kar` | notes and tempo; positions on the neck are worked out from the pitches, one part per instrument |
| MusicXML | `.musicxml` `.xml` `.mxl` | tablature staff (string, fret, fingering) when present, otherwise pitches; chord symbols; tuning and capo |
| Text tabs | `.txt` `.tab` | the six-line `e\|--0--3--\|` blocks from tab websites, chord names written above them; timing is guessed from the spacing, each bar between `\|` marks being one bar |
| Song file | `.json` | the app's own format below |

A file with several guitars becomes one song with a **part** chooser in the player. Fingers are suggested automatically when the file has none, the neck grows up to 24 frets when a song needs it, and the tuning and capo are shown in the player when they are not standard. Chord names found in the file become the "Easy: chords" track when the app knows the chord.

The readers live in `app/lib/import/` (one file per format) and are pure Dart, so they run in a background isolate. Test files for the Guitar Pro readers were written with [PyGuitarPro](https://github.com/Perlence/PyGuitarPro) (`app/test/fixtures/`).

## Adding songs to the catalog

Songs are JSON files in `songs/` (format in [docs/PLAN.md](docs/PLAN.md), section 5). The easiest way to add one is to write its melody and chords in `tools/make_songs.py` and run:

```
python3 tools/make_songs.py
```

This picks guitar positions and fingers, writes `songs/`, and copies the files into `app/assets/songs/` so they ship with the app. CI checks that the two folders match.

The app also downloads new songs from the public [guitar-learn-songs](https://github.com/mcbane23/guitar-learn-songs) repository, served free by GitHub Pages at `https://mcbane23.github.io/guitar-learn-songs/` (`index.json`, `chords.json` and one file per song, the same layout as `songs/` here). Publishing a song there makes it appear in the app without an update; the app keeps downloaded songs for offline use. The URL can be changed with `--dart-define=SONGS_URL=...`.
