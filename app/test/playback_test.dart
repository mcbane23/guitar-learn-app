import 'package:flutter_test/flutter_test.dart';
import 'package:guitar_learn/audio/synth.dart';
import 'package:guitar_learn/models/chord.dart';
import 'package:guitar_learn/models/song.dart';
import 'package:guitar_learn/playback/playback_controller.dart';
import 'package:guitar_learn/settings/settings.dart';
import 'package:guitar_learn/ui/scene_builder.dart';

Song _song() => Song.fromJson({
      'id': 'test',
      'title': {'en': 'Test'},
      'tempo': 60, // one beat per second at 100%
      'timeSignature': [4, 4],
      'tracks': {
        'full': [
          {'beat': 0, 'string': 2, 'fret': 1, 'finger': 1, 'length': 1},
          {'beat': 1, 'string': 1, 'fret': 0, 'finger': 0, 'length': 1},
          {'beat': 2, 'string': 1, 'fret': 3, 'finger': 3, 'length': 2},
          {'beat': 4, 'string': 3, 'fret': 2, 'finger': 2, 'length': 4},
        ],
        'easy': [
          {'beat': 0, 'chord': 'C', 'strum': 'down', 'length': 4},
          {'beat': 4, 'chord': 'G', 'strum': 'down', 'length': 4},
        ],
      },
    });

final _chords = ChordLibrary({
  'C': const ChordShape(name: 'C', frets: [0, 1, 0, 2, 3, -1], fingers: [0, 1, 0, 2, 3, 0]),
  'G': const ChordShape(name: 'G', frets: [3, 0, 0, 0, 2, 3], fingers: [3, 0, 0, 0, 1, 2]),
});

void main() {
  late double now;
  late RecordingSynth synth;
  late PlaybackController c;

  setUp(() {
    now = 0;
    synth = RecordingSynth();
    c = PlaybackController(
      song: _song(),
      chords: _chords,
      synth: synth,
      track: TrackKind.full,
      countIn: false,
      clock: () => now,
      autoTick: false,
    );
  });

  tearDown(() => c.dispose());

  test('moves through the song in time and plays notes a little ahead', () {
    c.play();
    c.tick();
    expect(synth.notes.map((n) => n.midi), [60]); // B string, fret 1 = C4
    now = 0.95;
    c.tick();
    expect(c.position, closeTo(0.95, 1e-9));
    expect(synth.notes.map((n) => n.midi), [60, 64]); // open high E scheduled early
    expect(synth.notes.last.delayMs, closeTo(50, 1));
  });

  test('speed slows the clock down', () {
    c.setSpeed(0.5);
    c.play();
    now = 1;
    c.tick();
    expect(c.position, closeTo(0.5, 1e-9));
  });

  test('finishes at the end of the song', () {
    c.play();
    now = 9;
    c.tick();
    expect(c.finished, isTrue);
    expect(c.isPlaying, isFalse);
    expect(c.position, c.totalBeats);
  });

  test('loop repeats two bars', () {
    c.seek(1);
    c.toggleLoop();
    expect(c.loop, (start: 0.0, end: 8.0));
    c.play();
    now = 7.5;
    c.tick();
    now = 8.5;
    c.tick();
    expect(c.position, closeTo(1.5, 1e-9)); // wrapped around (1 + 8.5 - 8)
    expect(c.finished, isFalse);
  });

  test('wait mode stops on each note until next()', () {
    c.setWaitMode(true);
    c.play();
    c.tick();
    expect(c.waiting, isTrue);
    expect(c.position, 0);
    now = 5;
    c.tick();
    expect(c.position, 0, reason: 'does not move while waiting');
    c.next();
    now = 6.5;
    c.tick();
    expect(c.waiting, isTrue);
    expect(c.position, 1);
  });

  test('count-in clicks three times before starting', () {
    c.countIn = true;
    c.play();
    expect(c.countdown, 3);
    expect(synth.clicks.length, 3);
    now = 1.5;
    c.tick();
    expect(c.countdown, 2);
    now = 3.2;
    c.tick();
    expect(c.countdown, isNull);
    expect(c.position, closeTo(0.2, 1e-9));
  });

  test('count-in takes one second per count at any speed', () {
    c.countIn = true;
    c.setSpeed(0.5);
    c.play();
    expect(c.countdown, 3);
    expect(synth.clicks.map((k) => k.delayMs), [0, 1000, 2000]);
    now = 2.5;
    c.tick();
    expect(c.countdown, 1);
    now = 3.0;
    c.tick();
    expect(c.countdown, isNull);
    expect(c.position, closeTo(0, 1e-9));
  });

  test('seekBars steps a bar at a time', () {
    c.seek(2.4);
    c.seekBars(1); // the next bar line
    expect(c.position, 4);
    c.seekBars(-1);
    expect(c.position, 0);
    c.seekBars(-1);
    expect(c.position, 0);
    c.seek(4.5); // just into bar 2: back goes to the previous bar
    c.seekBars(-1);
    expect(c.position, 0);
    c.seek(7.0); // deep into bar 2: back goes to its start
    c.seekBars(-1);
    expect(c.position, 4);
    c.seekBars(100);
    expect(c.position, c.totalBeats);
    c.seekBars(-1);
    expect(c.position, 4);
  });

  test('a second part plays along in its own tuning and swaps on handover', () {
    final song = Song.fromJson({
      'id': 'two',
      'title': {'en': 'Two'},
      'tempo': 60,
      'timeSignature': [4, 4],
      'tracks': {
        'full': [
          {'beat': 0, 'string': 1, 'fret': 0, 'finger': 0, 'length': 1},
        ],
      },
      'parts': [
        {'name': 'Lead', 'notes': [{'beat': 0, 'string': 1, 'fret': 0, 'finger': 0, 'length': 1}]},
        {
          'name': 'Bass',
          'tuning': ['D2', 'A2', 'D3', 'G3', 'B3', 'E4'],
          'notes': [{'beat': 0, 'string': 6, 'fret': 0, 'finger': 0, 'length': 1}],
        },
      ],
    });
    final c2 = PlaybackController(song: song, chords: _chords, synth: synth, countIn: false, clock: () => now, autoTick: false);
    c2.setSecondPart(1);
    expect(c2.secondSong?.parts[1].name, 'Bass');
    c2.play();
    c2.tick();
    // The open high E of the lead and the open low D of the bass sound together.
    expect(synth.notes.map((n) => n.midi).toSet(), {64, 38});
    expect(synth.notes.where((n) => n.midi == 38).single.string, 0); // never cuts a lead note

    // The bass becomes the main part: the lead moves to the second neck.
    final c3 = PlaybackController(song: song.withPart(1), chords: _chords, synth: synth, countIn: false, clock: () => now, autoTick: false)
      ..continueFrom(c2);
    expect(c3.secondPart, 0);
    expect(c3.isPlaying, isTrue);
    c2.dispose();
    expect(synth.stops, 0); // the hand-over does not silence the ringing notes
    c3.setSecondPart(null);
    expect(c3.secondSong, isNull);
    c3.dispose();
  });

  test('another part continues from the same place without a count-in', () {
    c.countIn = true;
    c.setSpeed(0.5);
    c.setMetronome(true);
    c.play();
    now = 3.0; // count-in over
    c.tick();
    now = 5.0; // one beat in at 50%
    c.tick();
    expect(c.position, closeTo(1.0, 1e-9));
    final other = PlaybackController(
        song: _song(), chords: _chords, synth: synth, countIn: true, clock: () => now, autoTick: false)
      ..continueFrom(c);
    expect(other.position, closeTo(1.0, 1e-9));
    expect(other.speed, 0.5);
    expect(other.metronome, isTrue);
    expect(other.countdown, isNull);
    expect(other.isPlaying, isTrue);
    now = 7.0;
    other.tick();
    expect(other.position, closeTo(2.0, 1e-9));
    other.dispose();
  });

  test('chord mode strums every string of the chord softly under the melody', () {
    c.setTrack(TrackKind.easy);
    c.play();
    c.tick();
    // C chord here plays strings 5..1 (string 6 muted), thick to thin: 48 52 55 60 64.
    final strum = synth.notes.where((n) => n.string == 0).toList();
    expect(strum.map((n) => n.midi), [48, 52, 55, 60, 64]);
    expect(strum.every((n) => n.velocity < 0.5), isTrue);
    // The melody's first note (B string, fret 1 = C4) sounds on top, louder.
    final melody = synth.notes.where((n) => n.string != 0).toList();
    expect(melody.map((n) => (n.string, n.midi)), [(2, 60)]);
    expect(melody.single.velocity, greaterThan(0.9));
    expect(c.currentChord, 'C');
  });

  test('a chords-only song strums the chords at full volume', () {
    final j = {
      'id': 'chordsonly',
      'title': {'en': 'Chords only'},
      'tempo': 60,
      'tracks': {
        'easy': [
          {'beat': 0, 'chord': 'C', 'strum': 'down', 'length': 4},
        ],
      },
    };
    final d = PlaybackController(
        song: Song.fromJson(j), chords: _chords, synth: synth, countIn: false, clock: () => now, autoTick: false);
    d.play();
    d.tick();
    expect(synth.notes.map((n) => n.string), [5, 4, 3, 2, 1]);
    expect(synth.notes.every((n) => n.velocity > 0.8), isTrue);
    d.dispose();
  });

  test('accompany mode plays chords quietly under the melody', () {
    c.setSoundMode(SoundMode.accompany);
    c.play();
    c.tick();
    expect(synth.notes.map((n) => n.string), [5, 4, 3, 2, 1]);
    expect(synth.notes.every((n) => n.velocity < 0.5), isTrue);
  });

  test('mute plays nothing', () {
    c.setSoundMode(SoundMode.mute);
    c.play();
    now = 3;
    c.tick();
    expect(synth.notes, isEmpty);
  });

  test('neck shows the current note and fades in the next one', () {
    c.play();
    now = 0.9;
    c.tick();
    final scene = buildScene(c, time: 0.5);
    final solid = scene.dots.where((d) => d.opacity == 1).toList();
    expect(solid.map((d) => (d.string, d.fret)), [(2, 1)]);
    // Next fretted note (string 1, fret 3 at beat 2) is within the preview window.
    expect(scene.dots.any((d) => d.string == 1 && d.fret == 3 && d.opacity < 1), isTrue);
    expect(scene.pluckAge.containsKey(2), isTrue);
  });

  test('the note to play now is the only full dot; the next ones are small and still', () {
    c.setSpeed(1);
    c.play();
    now = 0.1;
    c.tick();
    final first = buildScene(c, time: 0.1, preview: NotePreview.several);
    expect(first.dots.where((d) => d.now).map((d) => (d.string, d.fret)), [(2, 1)]);
    // Beat 1 is an open string: no dot, and beat 2 is past the look-ahead.
    expect(first.dots.where((d) => !d.now), isEmpty);

    now = 1.1;
    c.tick();
    final all = buildScene(c, time: 1.1, preview: NotePreview.several);
    expect(all.dots.where((d) => d.now), isEmpty);
    expect(all.openStrings, {1});
    final coming = all.dots.where((d) => !d.now).toList();
    expect(coming.map((d) => (d.string, d.fret)), [(1, 3)]);
    expect(coming.single.scale, lessThan(1));
    // The dots keep still: a moment later they are the same size and shade.
    now = 1.3;
    c.tick();
    final later = buildScene(c, time: 1.3, preview: NotePreview.several).dots.single;
    expect((later.string, later.fret, later.opacity, later.scale), (1, 3, coming.single.opacity, coming.single.scale));

    final next = buildScene(c, time: 1.3, preview: NotePreview.next);
    expect(next.dots.where((d) => !d.now).map((d) => (d.string, d.fret)), [(1, 3)]);
    final none = buildScene(c, time: 1.3, preview: NotePreview.none);
    expect(none.dots, isEmpty);
  });

  test('"the next one" shows one cue, "the next few" everything in the look-ahead', () {
    // At 100% the look-ahead is 1.2 beats.
    c.setSpeed(1);
    c.play();
    now = 2.9;
    c.tick();
    // Now: string 1 fret 3 (beat 2, two beats long). Next: beat 4 on string 3.
    final several = buildScene(c, time: 2.9, preview: NotePreview.several);
    expect(several.dots.where((d) => d.now).map((d) => (d.string, d.fret)), [(1, 3)]);
    expect(several.dots.where((d) => !d.now).map((d) => (d.string, d.fret)), [(3, 2)]);
    final next = buildScene(c, time: 2.9, preview: NotePreview.next);
    expect(next.dots.where((d) => !d.now).map((d) => (d.string, d.fret)), [(3, 2)]);
  });

  test('starts note by note, with chords as the alternative', () {
    final d = PlaybackController(song: _song(), chords: _chords, synth: synth, autoTick: false);
    expect(d.track, TrackKind.full);
    expect(d.soundModes, SoundMode.values);
    d.dispose();
  });

  test('a song without chords offers no chord mode or accompaniment', () {
    final j = {
      'id': 'nochords',
      'title': {'en': 'No chords'},
      'tracks': {
        'full': [
          {'beat': 0, 'string': 1, 'fret': 0, 'finger': 0, 'length': 1},
        ],
      },
    };
    final d = PlaybackController(song: Song.fromJson(j), chords: _chords, synth: synth, track: TrackKind.easy, autoTick: false);
    expect(d.track, TrackKind.full);
    d.setTrack(TrackKind.easy);
    expect(d.track, TrackKind.full);
    expect(d.soundModes, [SoundMode.song, SoundMode.mute]);
    d.nextSoundMode();
    expect(d.soundMode, SoundMode.mute);
    d.nextSoundMode();
    expect(d.soundMode, SoundMode.song);
    d.setSoundMode(SoundMode.accompany);
    expect(d.soundMode, SoundMode.song);
    d.dispose();
  });
}
