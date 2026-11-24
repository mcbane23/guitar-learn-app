/// The web page a phone shows after scanning the QR code on the TV.
///
/// It has no outside dependencies, so it works on any phone browser on a
/// Wi-Fi network without Internet access. Files go up one at a time with
/// `PUT /<code>/upload?name=<file name>`.
library;

import 'dart:convert';

import '../import/importer.dart' show supportedExtensions;
import '../l10n/strings.dart' show toCyrillic;

/// Text of the page in each language; Serbian Cyrillic is derived from Latin
/// by the app, so only Latin is listed here.
const _text = {
  'en': {
    'title': 'Send songs to {device}',
    'pick': 'Choose song files',
    'hint': 'Guitar Pro, MIDI, MusicXML or text tabs. You can choose several files at once.',
    'sending': 'Sending...',
    'added': 'Added',
    'already': 'Already there',
    'failed': 'Could not be read',
    'tooLarge': 'Too large',
    'unsupported': 'Not a song file',
    'noNotes': 'No notes in this file',
    'offline': 'The TV did not answer. Is the screen with the QR code still open?',
    'noCode': 'Open the link shown on the TV screen, or scan its QR code. The link ends with a 4-digit code.',
    'done': 'Done: {ok} of {n} files added. Look at the TV.',
  },
  'sr': {
    'title': 'Pošalji pesme na {device}',
    'pick': 'Izaberi fajlove sa pesmama',
    'hint': 'Guitar Pro, MIDI, MusicXML ili tekst tabulature. Možeš izabrati više fajlova odjednom.',
    'sending': 'Šalje se...',
    'added': 'Dodato',
    'already': 'Već postoji',
    'failed': 'Ne može da se pročita',
    'tooLarge': 'Prevelik fajl',
    'unsupported': 'Nije fajl sa pesmom',
    'noNotes': 'U fajlu nema nota',
    'offline': 'TV ne odgovara. Da li je ekran sa QR kodom još otvoren?',
    'noCode': 'Otvori link koji piše na TV ekranu ili skeniraj QR kod. Link se završava četvorocifrenim kodom.',
    'done': 'Gotovo: dodato {ok} od {n} fajlova. Pogledaj TV.',
  },
};

/// The whole page. [code] is null when the link had no (or a wrong) code.
String uploadPage({required String language, required String? code, required String deviceName}) {
  final cyrillic = language == 'sr-Cyrl';
  final t = _text[language == 'en' ? 'en' : 'sr']!;
  String s(String key) {
    var v = t[key]!.replaceAll('{device}', deviceName);
    return cyrillic ? toCyrillicText(v) : v;
  }

  final esc = const HtmlEscape(HtmlEscapeMode.element).convert;
  final accept = supportedExtensions.map((e) => '.$e').join(',');
  final strings = jsonEncode({for (final k in t.keys) k: s(k)});
  final body = code == null
      ? '<p class="big">${esc(s('noCode'))}</p>'
      : '''
<label class="button" for="files">${esc(s('pick'))}</label>
<input id="files" type="file" multiple accept="$accept">
<p class="hint">${esc(s('hint'))}</p>
<ul id="list"></ul>
<p id="summary" class="big"></p>
<script>
const T = $strings;
const code = ${jsonEncode(code)};
const input = document.getElementById('files');
const list = document.getElementById('list');
const summary = document.getElementById('summary');
function row(file) {
  const li = document.createElement('li');
  const name = document.createElement('span'); name.className = 'name'; name.textContent = file.name;
  const state = document.createElement('span'); state.className = 'state'; state.textContent = T.sending;
  li.appendChild(name); li.appendChild(state); list.appendChild(li);
  return state;
}
function describe(r) {
  if (r.ok) return r.alreadyAdded ? T.already : T.added;
  if (r.error === 'tooLarge') return T.tooLarge;
  if (r.error === 'unsupported') return T.unsupported;
  if (r.error === 'noNotes') return T.noNotes;
  return T.failed;
}
input.addEventListener('change', async () => {
  const files = Array.from(input.files);
  input.value = '';
  summary.textContent = '';
  let ok = 0;
  for (const file of files) {
    const state = row(file);
    try {
      const res = await fetch('/' + code + '/upload?name=' + encodeURIComponent(file.name), {method: 'PUT', body: file});
      const r = await res.json();
      state.textContent = describe(r);
      state.className = 'state ' + (r.ok ? 'ok' : 'bad');
      if (r.ok) ok++;
    } catch (e) {
      state.textContent = T.offline;
      state.className = 'state bad';
    }
  }
  summary.textContent = T.done.replace('{ok}', ok).replace('{n}', files.length);
});
</script>''';
  return '''<!DOCTYPE html>
<html lang="${esc(language)}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(s('title'))}</title>
<style>
body { font-family: system-ui, sans-serif; margin: 0; padding: 24px 20px; background: #15161c; color: #f2f2f6; }
h1 { font-size: 24px; margin: 0 0 20px; }
.button { display: block; background: #f5a524; color: #1a1200; text-align: center; font-size: 22px; font-weight: 700; padding: 20px; border-radius: 16px; cursor: pointer; }
input[type=file] { display: none; }
.hint { color: #b7b8c4; font-size: 16px; }
.big { font-size: 20px; line-height: 1.4; }
ul { list-style: none; padding: 0; margin: 20px 0; }
li { display: flex; justify-content: space-between; gap: 12px; padding: 12px 0; border-bottom: 1px solid #2d2f3a; font-size: 17px; }
.name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.state { flex: none; color: #b7b8c4; }
.ok { color: #6fdc8c; } .bad { color: #ff7b7b; }
</style>
</head>
<body>
<h1>${esc(s('title'))}</h1>
$body
</body>
</html>
''';
}

/// Serbian Latin to Cyrillic, the same rules as the app's [toCyrillic].
String toCyrillicText(String latin) => toCyrillic(latin);
