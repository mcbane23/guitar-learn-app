#!/usr/bin/env python3
"""Builds the song JSON files from short melody descriptions.

Each song below is written as a melody in note names (C4, F#3, r = rest) with
beat lengths, plus a chord progression. The script picks the easiest guitar
position for every note (lowest fret, first position), assigns fingers, and
writes:

  songs/<id>.json      one file per song (format in docs/PLAN.md, section 5)
  songs/chords.json    finger positions for every chord used
  songs/index.json     the catalog the app downloads

and mirrors everything into app/assets/songs/ so the app ships with it.

Run from the repo root:  python3 tools/make_songs.py
"""

import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "songs")
APP_OUT = os.path.join(ROOT, "app", "assets", "songs")

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
# Standard tuning, string 1 (thin, high E) to string 6 (thick, low E).
STANDARD = {1: 64, 2: 59, 3: 55, 4: 50, 5: 45, 6: 40}

# Chord shapes, listed from string 6 to string 1. -1 = do not play the string.
CHORDS = {
    "C":  ([-1, 3, 2, 0, 1, 0], [0, 3, 2, 0, 1, 0]),
    "D":  ([-1, -1, 0, 2, 3, 2], [0, 0, 0, 1, 3, 2]),
    "Dm": ([-1, -1, 0, 2, 3, 1], [0, 0, 0, 2, 3, 1]),
    "E":  ([0, 2, 2, 1, 0, 0], [0, 2, 3, 1, 0, 0]),
    "Em": ([0, 2, 2, 0, 0, 0], [0, 2, 3, 0, 0, 0]),
    "F":  ([-1, -1, 3, 2, 1, 1], [0, 0, 3, 2, 1, 1]),
    "G":  ([3, 2, 0, 0, 0, 3], [2, 1, 0, 0, 0, 3]),
    "A":  ([-1, 0, 2, 2, 2, 0], [0, 0, 1, 2, 3, 0]),
    "Am": ([-1, 0, 2, 2, 1, 0], [0, 0, 2, 3, 1, 0]),
    "B7": ([-1, 2, 1, 2, 0, 2], [0, 2, 1, 3, 0, 4]),
    "C7": ([-1, 3, 2, 3, 1, 0], [0, 3, 2, 4, 1, 0]),
    "D7": ([-1, -1, 0, 2, 1, 2], [0, 0, 0, 2, 1, 3]),
    "E7": ([0, 2, 0, 1, 0, 0], [0, 2, 0, 1, 0, 0]),
    "G7": ([3, 2, 0, 0, 0, 1], [3, 2, 0, 0, 0, 1]),
    "A7": ([-1, 0, 2, 0, 2, 0], [0, 0, 2, 0, 3, 0]),
}


def midi(name):
    """'C4' -> 60, 'F#3' -> 54."""
    letter = name[0]
    rest = name[1:]
    acc = 0
    while rest and rest[0] in "#b":
        acc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return (int(rest) + 1) * 12 + NOTE_INDEX[letter] + acc


def position(m, prev_string):
    """Easiest (string, fret) for a MIDI note: lowest fret, then nearest string."""
    options = []
    for s, open_midi in STANDARD.items():
        fret = m - open_midi
        if 0 <= fret <= 5:
            options.append((fret, abs(s - prev_string) if prev_string else 0, s))
    if not options:
        raise ValueError(f"note {m} is outside first position")
    # Prefer frets 0-4 (one finger per fret), then fewest string jumps.
    options.sort(key=lambda o: (o[0] > 4, o[0], o[1]))
    fret, _, s = options[0]
    return s, fret


def parse_seq(text):
    """'C4:1 D4:0.5 r:1' -> [('C4', 1.0), ('D4', 0.5), ('r', 1.0)]"""
    out = []
    for tok in text.split():
        name, length = tok.split(":")
        out.append((name, float(eval(length))))  # lengths may be written as 1/3
    return out


def build(song):
    full = []
    beat = 0.0
    prev = None
    for name, length in parse_seq(song["melody"]):
        if name != "r":
            s, fret = position(midi(name), prev)
            prev = s
            finger = 0 if fret == 0 else min(fret, 4)
            full.append({"beat": round(beat, 4), "string": s, "fret": fret,
                         "finger": finger, "length": round(length, 4)})
        beat += length
    total = beat

    easy = []
    beat = 0.0
    bpb = song.get("beatsPerBar", song["timeSignature"][0])
    every = song.get("strumEvery", 1)
    for name, length in parse_seq(song["chords"]):
        if name != "r":
            if name not in CHORDS:
                raise ValueError(f"unknown chord {name}")
            # One strum per beat: a down strum on the first beat of the bar,
            # then alternating down/up, which is how beginners learn to strum.
            b = beat
            end = beat + length
            while b < end - 1e-6:
                step = min(float(every), end - b)
                in_bar = round(b % bpb, 4)
                strum = "down" if int(in_bar / every) % 2 == 0 else "up"
                easy.append({"beat": round(b, 4), "chord": name, "strum": strum,
                             "length": round(step, 4)})
                b += step
        beat += length
    if abs(beat - total) > 1e-6:
        raise ValueError(f"{song['id']}: chords last {beat} beats, melody {total}")

    return {
        "id": song["id"],
        "title": song["title"],
        "artist": song["artist"],
        "license": "public-domain",
        "source": song["source"],
        "language": "instrumental",
        "difficulty": song["difficulty"],
        "tags": song["tags"],
        "tempo": song["tempo"],
        "timeSignature": song["timeSignature"],
        "beatsPerBar": song.get("beatsPerBar", song["timeSignature"][0]),
        "tuning": ["E2", "A2", "D3", "G3", "B3", "E4"],
        "capo": 0,
        "tracks": {"full": full, "easy": easy},
    }


TRAD = "Traditional"

SONGS = [
    {
        "id": "twinkle-twinkle",
        "title": {"en": "Twinkle, Twinkle, Little Star", "sr": "Sijaj, sijaj, zvezdice"},
        "artist": TRAD, "source": "Traditional melody (18th century French 'Ah! vous dirai-je, maman')",
        "difficulty": "easy", "tags": ["kids", "beginner"], "tempo": 96, "timeSignature": [4, 4],
        "melody": """
            C3:1 C3:1 G3:1 G3:1 A3:1 A3:1 G3:2  F3:1 F3:1 E3:1 E3:1 D3:1 D3:1 C3:2
            G3:1 G3:1 F3:1 F3:1 E3:1 E3:1 D3:2  G3:1 G3:1 F3:1 F3:1 E3:1 E3:1 D3:2
            C3:1 C3:1 G3:1 G3:1 A3:1 A3:1 G3:2  F3:1 F3:1 E3:1 E3:1 D3:1 D3:1 C3:2
        """,
        "chords": "C:4 F:2 C:2 F:2 C:2 G:2 C:2  C:2 F:2 C:2 G:2 C:2 F:2 C:2 G:2  C:4 F:2 C:2 F:2 C:2 G:2 C:2",
    },
    {
        "id": "mary-had-a-little-lamb",
        "title": {"en": "Mary Had a Little Lamb", "sr": "Meri je imala jagnje"},
        "artist": TRAD, "source": "Traditional American nursery song (1830)",
        "difficulty": "easy", "tags": ["kids", "beginner"], "tempo": 100, "timeSignature": [4, 4],
        "melody": """
            E3:1 D3:1 C3:1 D3:1 E3:1 E3:1 E3:2  D3:1 D3:1 D3:2 E3:1 G3:1 G3:2
            E3:1 D3:1 C3:1 D3:1 E3:1 E3:1 E3:1 E3:1  D3:1 D3:1 E3:1 D3:1 C3:4
        """,
        "chords": "C:8 G:4 C:4 C:8 G:4 C:4",
    },
    {
        "id": "ode-to-joy",
        "title": {"en": "Ode to Joy", "sr": "Oda radosti"},
        "artist": "Ludwig van Beethoven", "source": "Symphony No. 9 (1824), theme",
        "difficulty": "easy", "tags": ["classical", "beginner"], "tempo": 100, "timeSignature": [4, 4],
        "melody": """
            E3:1 E3:1 F3:1 G3:1 G3:1 F3:1 E3:1 D3:1 C3:1 C3:1 D3:1 E3:1 E3:1.5 D3:0.5 D3:2
            E3:1 E3:1 F3:1 G3:1 G3:1 F3:1 E3:1 D3:1 C3:1 C3:1 D3:1 E3:1 D3:1.5 C3:0.5 C3:2
            D3:1 D3:1 E3:1 C3:1 D3:1 E3:0.5 F3:0.5 E3:1 C3:1 D3:1 E3:0.5 F3:0.5 E3:1 D3:1 C3:1 D3:1 G2:2
            E3:1 E3:1 F3:1 G3:1 G3:1 F3:1 E3:1 D3:1 C3:1 C3:1 D3:1 E3:1 D3:1.5 C3:0.5 C3:2
        """,
        "chords": """
            C:4 G:4 C:4 G:4
            C:4 G:4 C:4 G:2 C:2
            G:2 C:2 G:2 C:2 G:2 C:2 G:4
            C:4 G:4 C:4 G:2 C:2
        """,
    },
    {
        "id": "frere-jacques",
        "title": {"en": "Frère Jacques (Are You Sleeping?)", "sr": "Bratec Martin"},
        "artist": TRAD, "source": "Traditional French round (18th century)",
        "difficulty": "easy", "tags": ["kids", "beginner"], "tempo": 100, "timeSignature": [4, 4],
        "melody": """
            C3:1 D3:1 E3:1 C3:1  C3:1 D3:1 E3:1 C3:1  E3:1 F3:1 G3:2  E3:1 F3:1 G3:2
            G3:0.5 A3:0.5 G3:0.5 F3:0.5 E3:1 C3:1  G3:0.5 A3:0.5 G3:0.5 F3:0.5 E3:1 C3:1
            C3:1 G2:1 C3:2  C3:1 G2:1 C3:2
        """,
        "chords": "C:16 C:4 C:4 C:1 G:1 C:2 C:1 G:1 C:2",
    },
    {
        "id": "happy-birthday",
        "title": {"en": "Happy Birthday to You", "sr": "Srećan rođendan"},
        "artist": "Mildred J. Hill and Patty Hill", "source": "'Good Morning to All' (1893); public domain",
        "difficulty": "easy", "tags": ["kids", "beginner"], "tempo": 110, "timeSignature": [3, 4],
        "melody": """
            r:2 G2:0.75 G2:0.25 A2:1 G2:1 C3:1 B2:2
            G2:0.75 G2:0.25 A2:1 G2:1 D3:1 C3:2
            G2:0.75 G2:0.25 G3:1 E3:1 C3:1 B2:1 A2:1
            F3:0.75 F3:0.25 E3:1 C3:1 D3:1 C3:2 r:1
        """,
        "chords": "C:3 C:3 G:3 G:3 C:3 C7:3 F:3 C:2 G:1 C:3",
    },
    {
        "id": "row-your-boat",
        "title": {"en": "Row, Row, Row Your Boat", "sr": "Veslaj, veslaj čamcem"},
        "artist": TRAD, "source": "Traditional nursery song (1852)",
        "difficulty": "easy", "tags": ["kids", "beginner"], "tempo": 60, "timeSignature": [6, 8], "beatsPerBar": 2,
        # 6/8 time: one beat is a dotted quarter note, so eighth notes are 1/3.
        "melody": """
            C3:1 C3:1 C3:2/3 D3:1/3 E3:1 E3:2/3 D3:1/3 E3:2/3 F3:1/3 G3:2
            C4:1/3 C4:1/3 C4:1/3 G3:1/3 G3:1/3 G3:1/3 E3:1/3 E3:1/3 E3:1/3 C3:1/3 C3:1/3 C3:1/3
            G3:2/3 F3:1/3 E3:2/3 D3:1/3 C3:2
        """,
        "chords": "C:12 G:2 C:2",
    },
    {
        "id": "old-macdonald",
        "title": {"en": "Old MacDonald Had a Farm", "sr": "Stari Mekdonald ima farmu"},
        "artist": TRAD, "source": "Traditional children's song",
        "difficulty": "easy", "tags": ["kids", "beginner"], "tempo": 112, "timeSignature": [4, 4],
        "melody": """
            G3:1 G3:1 G3:1 D3:1 E3:1 E3:1 D3:2  B3:1 B3:1 A3:1 A3:1 G3:3 D3:1
            G3:1 G3:1 G3:1 D3:1 E3:1 E3:1 D3:2  B3:1 B3:1 A3:1 A3:1 G3:4
        """,
        "chords": "G:4 C:2 G:2 G:2 D:2 G:4 G:4 C:2 G:2 G:2 D:2 G:4",
    },
    {
        "id": "jingle-bells",
        "title": {"en": "Jingle Bells", "sr": "Zvončići"},
        "artist": "James Lord Pierpont", "source": "'One Horse Open Sleigh' (1857), chorus",
        "difficulty": "medium", "tags": ["holidays", "kids"], "tempo": 120, "timeSignature": [4, 4],
        "melody": """
            E3:1 E3:1 E3:2  E3:1 E3:1 E3:2  E3:1 G3:1 C3:1.5 D3:0.5 E3:4
            F3:1 F3:1 F3:1.5 F3:0.5 F3:1 E3:1 E3:1 E3:0.5 E3:0.5 E3:1 D3:1 D3:1 E3:1 D3:2 G3:2
            E3:1 E3:1 E3:2  E3:1 E3:1 E3:2  E3:1 G3:1 C3:1.5 D3:0.5 E3:4
            F3:1 F3:1 F3:1.5 F3:0.5 F3:1 E3:1 E3:1 E3:0.5 E3:0.5 G3:1 G3:1 F3:1 D3:1 C3:4
        """,
        "chords": "C:16 F:4 C:4 D7:4 G:4  C:16 F:4 C:4 G:4 C:4",
    },
    {
        "id": "when-the-saints",
        "title": {"en": "When the Saints Go Marching In", "sr": "Kad sveci krenu u marš"},
        "artist": TRAD, "source": "Traditional American spiritual",
        "difficulty": "easy", "tags": ["folk", "beginner"], "tempo": 120, "timeSignature": [4, 4],
        "melody": """
            r:1 C3:1 E3:1 F3:1 G3:4  r:1 C3:1 E3:1 F3:1 G3:4
            r:1 C3:1 E3:1 F3:1 G3:2 E3:2 C3:2 E3:2 D3:4
            r:2 E3:1 D3:1 C3:3 C3:1 E3:2 G3:2 G3:1 F3:3
            r:1 E3:1 F3:1 G3:1 E3:2 C3:2 D3:2 C3:4 r:2
        """,
        "chords": "C:16 C:12 G:4  C:8 C7:4 F:4  C:4 C:4 G:2 C:6",
    },
    {
        "id": "amazing-grace",
        "title": {"en": "Amazing Grace", "sr": "Čudesna milost"},
        "artist": "John Newton (words), traditional melody 'New Britain'", "source": "Traditional (1779 / 1829)",
        "difficulty": "medium", "tags": ["folk"], "tempo": 84, "timeSignature": [3, 4],
        "melody": """
            r:2 D3:1 G3:2 B3:0.5 G3:0.5 B3:2 A3:1 G3:2 E3:1 D3:2 D3:1
            G3:2 B3:0.5 G3:0.5 B3:2 A3:1 D4:3 D4:2 B3:1
            D4:1.5 B3:0.5 D4:0.5 B3:0.5 G3:2 D3:1 E3:1.5 G3:0.5 G3:0.5 E3:0.5 D3:2 D3:1
            G3:2 B3:0.5 G3:0.5 B3:2 A3:1 G3:3 G3:3
        """,
        "chords": "G:3 G:3 G:3 C:3 G:3 G:3 G:3 D:3 D:3 G:3 Em:3 C:3 G:3 G:3 D:3 G:3 G:3",
    },
    {
        "id": "silent-night",
        "title": {"en": "Silent Night", "sr": "Tiha noć"},
        "artist": "Franz Xaver Gruber", "source": "'Stille Nacht' (1818)",
        "difficulty": "medium", "tags": ["holidays"], "tempo": 80, "timeSignature": [3, 4],
        "melody": """
            G3:1.5 A3:0.5 G3:1 E3:3  G3:1.5 A3:0.5 G3:1 E3:3
            D4:2 D4:1 B3:3  C4:2 C4:1 G3:3
            A3:2 A3:1 C4:1.5 B3:0.5 A3:1 G3:1.5 A3:0.5 G3:1 E3:3
            A3:2 A3:1 C4:1.5 B3:0.5 A3:1 G3:1.5 A3:0.5 G3:1 E3:3
            D4:2 D4:1 F4:1.5 D4:0.5 B3:1 C4:3 E4:3
            C4:1.5 G3:0.5 E3:1 G3:1.5 F3:0.5 D3:1 C3:6
        """,
        "chords": "C:12 G:6 C:6 F:6 C:6 F:6 C:6 G:6 C:6 C:3 G:3 C:6",
    },
    {
        "id": "greensleeves",
        "title": {"en": "Greensleeves", "sr": "Grinslivs (Zeleni rukavi)"},
        "artist": TRAD, "source": "Traditional English (16th century)",
        "difficulty": "medium", "tags": ["classical", "folk"], "tempo": 96, "timeSignature": [3, 4],
        "melody": """
            r:2 A2:1 C3:2 D3:1 E3:1.5 F3:0.5 E3:1 D3:2 B2:1 G2:1.5 A2:0.5 B2:1
            C3:2 A2:1 A2:1.5 G#2:0.5 A2:1 B2:2 G#2:1 E2:2 A2:1
            C3:2 D3:1 E3:1.5 F3:0.5 E3:1 D3:2 B2:1 G2:1.5 A2:0.5 B2:1
            C3:1.5 B2:0.5 A2:1 G#2:1.5 F#2:0.5 G#2:1 A2:3 A2:2 r:1
            G3:3 G3:1.5 F#3:0.5 E3:1 D3:2 B2:1 G2:1.5 A2:0.5 B2:1
            C3:2 A2:1 A2:1.5 G#2:0.5 A2:1 B2:2 G#2:1 E2:3
            G3:3 G3:1.5 F#3:0.5 E3:1 D3:2 B2:1 G2:1.5 A2:0.5 B2:1
            C3:1.5 B2:0.5 A2:1 G#2:1.5 F#2:0.5 G#2:1 A2:3 A2:3
        """,
        "chords": """
            Am:3  Am:3 C:3 G:3 G:3  Am:3 Am:3 E:3 E:3  Am:3 C:3 G:3 G:3  Am:3 E:3 Am:3 Am:3
            C:3 G:3 G:3 Em:3  Am:3 Am:3 E:3 E:3  C:3 G:3 G:3 Em:3  Am:3 E:3 Am:3 Am:3
        """,
    },
    {
        "id": "fur-elise",
        "title": {"en": "Für Elise (theme)", "sr": "Za Elizu (tema)"},
        "artist": "Ludwig van Beethoven", "source": "Bagatelle No. 25 in A minor (1810), opening theme",
        "difficulty": "hard", "tags": ["classical"], "tempo": 110, "timeSignature": [3, 8],
        "strumEvery": 3,
        # 3/8 time: one beat is an eighth note, sixteenth notes are 0.5.
        "melody": """
            r:2 E4:0.5 D#4:0.5
            E4:0.5 D#4:0.5 E4:0.5 B3:0.5 D4:0.5 C4:0.5  A3:1 r:0.5 C3:0.5 E3:0.5 A3:0.5
            B3:1 r:0.5 E3:0.5 G#3:0.5 B3:0.5  C4:1 r:0.5 E3:0.5 E4:0.5 D#4:0.5
            E4:0.5 D#4:0.5 E4:0.5 B3:0.5 D4:0.5 C4:0.5  A3:1 r:0.5 C3:0.5 E3:0.5 A3:0.5
            B3:1 r:0.5 E3:0.5 C4:0.5 B3:0.5  A3:3
        """,
        "chords": "Am:3 Am:3 Am:3 E:3 Am:3 Am:3 Am:3 E:3 Am:3",
    },
]


def dump_song(song):
    """JSON with one note/chord event per line, so song files are easy to edit by hand."""
    head = {k: v for k, v in song.items() if k != "tracks"}
    text = json.dumps(head, ensure_ascii=False, indent=2)[:-2]
    parts = []
    for name, events in song["tracks"].items():
        lines = ",\n".join("      " + json.dumps(e, ensure_ascii=False) for e in events)
        parts.append(f'    "{name}": [\n{lines}\n    ]')
    return text + ',\n  "tracks": {\n' + ",\n".join(parts) + "\n  }\n}\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    used_chords = set()
    index = []
    for spec in SONGS:
        song = build(spec)
        used_chords.update(e["chord"] for e in song["tracks"]["easy"])
        path = os.path.join(OUT, f"{song['id']}.json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(dump_song(song))
        index.append({
            "id": song["id"],
            "file": f"{song['id']}.json",
            "title": song["title"],
            "artist": song["artist"],
            "language": song["language"],
            "difficulty": song["difficulty"],
            "tags": song["tags"],
            "version": 1,
        })

    chords = {name: {"frets": frets, "fingers": fingers}
              for name, (frets, fingers) in CHORDS.items()}
    with open(os.path.join(OUT, "chords.json"), "w", encoding="utf-8") as f:
        json.dump({"order": "string 6 to string 1", "chords": chords}, f, ensure_ascii=False, indent=2)
        f.write("\n")
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "songs": index}, f, ensure_ascii=False, indent=2)
        f.write("\n")

    missing = used_chords - CHORDS.keys()
    assert not missing, missing

    shutil.rmtree(APP_OUT, ignore_errors=True)
    shutil.copytree(OUT, APP_OUT)
    print(f"wrote {len(index)} songs, {len(chords)} chords")


if __name__ == "__main__":
    main()
