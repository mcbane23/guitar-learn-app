# Guitar Learn App

A free play-along guitar app for school kids and adults who can't read music. A full-screen guitar neck shows where to press and which string to play, and the app plays the guitar sound live from the same notes, with no pre-recorded audio.

- Platforms: Android phone, tablet and Android TV (Flutter)
- Languages: English and Serbian
- Songs: public-domain songs to start, with new songs downloaded from the Internet

See [docs/PLAN.md](docs/PLAN.md) for the full plan, feature list and milestones.

## Download a test build

Every push to `main` builds a debug APK and publishes it on the [Releases page](../../releases/latest). On the phone, tablet or TV, download the `.apk` file and open it; allow "install from unknown sources" when Android asks. Debug builds install next to each other as updates of the same app.

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

## Adding songs

Songs are JSON files in `songs/` (format in [docs/PLAN.md](docs/PLAN.md), section 5). The easiest way to add one is to write its melody and chords in `tools/make_songs.py` and run:

```
python3 tools/make_songs.py
```

This picks guitar positions and fingers, writes `songs/`, and copies the files into `app/assets/songs/` so they ship with the app. CI checks that the two folders match.

The app also downloads `index.json` and new song files from `SONGS_URL` (default `https://mcbane23.github.io/guitar-learn-app/songs/`, change it with `--dart-define=SONGS_URL=...`) and keeps them for offline use. The `Publish songs` workflow publishes `songs/` to GitHub Pages; Pages must be enabled for the repository (Settings > Pages > Source: GitHub Actions), which for a private repository needs a paid GitHub plan or a separate public songs repository.
