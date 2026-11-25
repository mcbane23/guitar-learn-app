import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../data/search.dart';
import '../data/song_repository.dart';
import '../l10n/strings.dart';
import '../models/song.dart';
import '../settings/settings.dart';
import '../update/app_update.dart';
import 'add_songs.dart';
import 'chords_screen.dart';
import 'common.dart';
import 'themes.dart';
import 'free_play_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();
  Difficulty? _difficulty;
  bool _refreshStarted = false;
  AppUpdate? _update;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_refreshStarted) {
      _refreshStarted = true;
      // Look for new online songs in the background; tell the user only if some arrived.
      final services = AppServices.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final (result, count) = await services.songs.refresh();
        if (!mounted || result != RefreshResult.added) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).newSongs(count))));
      });
      // Also look for a newer build of the app; a card at the top offers it.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final update = await services.updater.check();
        if (mounted && update != null) setState(() => _update = update);
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(SongInfo song) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(songId: song.id)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final repo = AppServices.of(context).songs;
    final settings = SettingsScope.of(context);
    return Scaffold(
      body: AppBackground(
        theme: settings.colorTheme,
        child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([repo, _query]),
          builder: (context, _) {
            final all = repo.songs;
            final mine = repo.importedSongs;
            final byId = {for (final s in all) s.id: s};
            final recent = [for (final id in settings.recentSongs) if (byId[id] case final s?) s];
            final searching = _query.text.trim().isNotEmpty || _difficulty != null;
            return CustomScrollView(
              slivers: [
                // Every sliver is keyed: when a row appears (the first
                // "Recently played") the rows under it keep their widgets,
                // and so the remote's focus.
                SliverToBoxAdapter(key: const ValueKey('header'), child: _header(context, t)),
                if (_update case final update?)
                  SliverToBoxAdapter(
                    key: const ValueKey('update'),
                    child: UpdateBanner(update: update, onDismiss: () => setState(() => _update = null)),
                  ),
                SliverToBoxAdapter(key: const ValueKey('search'), child: _searchBar(context, t)),
                if (searching)
                  _results(context, t, searchSongs(all, _query.text, difficulty: _difficulty))
                else ...[
                  if (recent.isNotEmpty)
                    SliverToBoxAdapter(
                      key: const ValueKey('continue'),
                      child: _ContinueCard(
                        song: recent.first,
                        onTap: () => _open(recent.first),
                        onLongPress: repo.isImported(recent.first.id)
                            ? () => removeImportedSongFlow(context, recent.first.id)
                            : null,
                      ),
                    ),
                  if (mine.isNotEmpty)
                    _section(context, t, t.mySongs, mine, autofocus: true, removable: true, addCard: true),
                  if (recent.isNotEmpty) _section(context, t, t.recentlyPlayed, recent, removable: true),
                  // Beginners land on the easiest songs first.
                  _section(context, t, t.beginner, all.where((s) => s.tags.contains('beginner')).toList(),
                      autofocus: mine.isEmpty),
                  _section(context, t, t.kids, all.where((s) => s.tags.contains('kids')).toList()),
                  _section(context, t, t.serbianFolk, all.where((s) => s.tags.contains('serbian-folk')).toList()),
                  _section(context, t, t.allSongs, all, removable: true),
                  if (mine.isEmpty)
                    SliverToBoxAdapter(
                      key: const ValueKey('add banner'),
                      child: _AddSongsBanner(onTap: () => addSongsFlow(context)),
                    ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Strings t) {
    void push(Widget Function() page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page()));
    final scheme = Theme.of(context).colorScheme;
    final actions = [
      _Action(Icons.grid_view_rounded, t.chords, scheme.primary, () => push(() => const ChordsScreen())),
      _Action(Icons.touch_app_rounded, t.freePlay, scheme.secondary, () => push(() => const FreePlayScreen())),
      _Action(Icons.file_open_rounded, t.addSongs, const Color(0xFFB48CFF), () => addSongsFlow(context)),
      _Action(Icons.settings_rounded, t.settings, const Color(0xFFF4F6FB), () => push(() => const SettingsScreen())),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45), blurRadius: 18)],
            ),
            child: Icon(Icons.music_note_rounded, size: 26, color: Theme.of(context).colorScheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Text(
            t.appTitle,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
        ]),
        const SizedBox(height: 10),
        // The four places to go, as big cards: easy to hit with a finger and
        // easy to see with a remote. Side by side on a TV or tablet, two by
        // two on a phone.
        LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 720;
          final width = wide ? (box.maxWidth - 12 * 3) / 4 : (box.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final a in actions) _ActionCard(action: a, width: width)],
          );
        }),
      ]),
    );
  }

  Widget _searchBar(BuildContext context, Strings t) {
    // Each level is colored like its song cards, so the filter and the
    // cards speak the same language.
    Widget chip(String label, Difficulty? d) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            selected: _difficulty == d,
            selectedColor: d == null ? null : _difficultyColors[d],
            avatar: d == null ? null : Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _difficulty == d ? Colors.black45 : _difficultyColors[d])),
            labelStyle: TextStyle(color: _difficulty == d && d != null ? const Color(0xFF14101E) : null),
            onSelected: (_) => setState(() => _difficulty = d),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: _SearchBox(controller: _query, hint: t.searchHint),
          ),
          const SizedBox(width: 16),
          chip(t.all, null),
          chip(t.easy, Difficulty.easy),
          chip(t.medium, Difficulty.medium),
          chip(t.hard, Difficulty.hard),
        ],
      ),
    );
  }

  /// A row of song cards. With [removable], holding a card that came from
  /// a file offers to remove it; with [addCard], the row ends with a card
  /// that opens more files.
  Widget _section(
    BuildContext context,
    Strings t,
    String title,
    List<SongInfo> songs, {
    bool autofocus = false,
    bool removable = false,
    bool addCard = false,
  }) {
    final repo = AppServices.of(context).songs;
    final count = songs.length + (addCard ? 1 : 0);
    return SliverToBoxAdapter(
      key: ValueKey('section $title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 148,
            child: songs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _ComingSoonCard(label: t.comingSoon),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    // A card keeps its widget (and the remote's focus) when
                    // the row reorders: "Recently played" moves the song
                    // that was just opened to the front.
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      final i = songs.indexWhere((s) => s.id == key.value);
                      return i < 0 ? null : i * 2; // items sit between separators
                    },
                    itemBuilder: (context, i) {
                      if (i == songs.length) return _AddSongsCard(onTap: () => addSongsFlow(context));
                      final song = songs[i];
                      final imported = repo.isImported(song.id);
                      return SongCard(
                        key: ValueKey(song.id),
                        song: song,
                        imported: imported,
                        autofocus: autofocus && i == 0,
                        onTap: () => _open(song),
                        onLongPress: removable && imported ? () => removeImportedSongFlow(context, song.id) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, Strings t, List<SongInfo> songs) {
    final repo = AppServices.of(context).songs;
    if (songs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Center(child: Text(t.noResults, style: Theme.of(context).textTheme.titleLarge)),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          mainAxisExtent: 132,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: songs.length,
        itemBuilder: (context, i) => SongCard(
          song: songs[i],
          imported: repo.isImported(songs[i].id),
          onTap: () => _open(songs[i]),
          onLongPress: repo.isImported(songs[i].id) ? () => removeImportedSongFlow(context, songs[i].id) : null,
        ),
      ),
    );
  }
}

/// The search field. With a remote, moving through the screen stops on it
/// like on a button, without opening the keyboard; OK starts typing, and
/// up or down leaves the field again. Touch works as usual.
class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final _stop = FocusNode(debugLabel: 'search');
  final _field = FocusNode(debugLabel: 'search field', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    _stop.addListener(_changed);
    _field.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _stop.dispose();
    _field.dispose();
    super.dispose();
  }

  KeyEventResult _onStopKey(FocusNode node, KeyEvent e) {
    if (!_stop.hasPrimaryFocus || e is! KeyDownEvent) return KeyEventResult.ignored;
    if (isOkKey(e.logicalKey)) {
      _field.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Leaves the field in [direction], as if it were a button.
  void _leave(TraversalDirection direction) {
    _stop.requestFocus();
    _stop.focusInDirection(direction);
  }

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(28),
      borderSide: _stop.hasPrimaryFocus ? const BorderSide(color: Colors.white, width: 3) : BorderSide.none,
    );
    return Focus(
      focusNode: _stop,
      onKeyEvent: _onStopKey,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _leave(TraversalDirection.down),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _leave(TraversalDirection.up),
        },
        child: TextField(
          controller: widget.controller,
          focusNode: _field,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 16),
          onSubmitted: (_) => _stop.requestFocus(),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: widget.controller.text.isEmpty
                ? null
                : ExcludeFocus(child: IconButton(icon: const Icon(Icons.clear), onPressed: widget.controller.clear)),
            filled: true,
            border: border,
            enabledBorder: border,
          ),
        ),
      ),
    );
  }
}

/// One color per level, used for the dot on the song cards and the filter chips.
const _difficultyColors = {
  Difficulty.easy: Color(0xFF4CE0A0),
  Difficulty.medium: Color(0xFFFFC93C),
  Difficulty.hard: Color(0xFFFF6B8A),
};

/// A small pill with a colored dot and the name of the level.
class _DifficultyChip extends StatelessWidget {
  const _DifficultyChip(this.difficulty);

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: glassHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _difficultyColors[difficulty]),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            t.difficulty(difficulty.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
          ),
        ),
      ]),
    );
  }
}

class SongCard extends StatelessWidget {
  const SongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.imported = false,
  });

  final SongInfo song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;

  /// The song came from a file on this device.
  final bool imported;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final subtitle = song.artist.isNotEmpty ? song.artist : (imported ? (song.format ?? t.fromFile) : '');
    return FocusCard(
      width: 190,
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(child: _DifficultyChip(song.difficulty)),
              const Spacer(),
              Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 26),
            ]),
            const Spacer(),
            Text(
              t.songTitle(song),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15),
            ),
            const SizedBox(height: 4),
            Row(children: [
              if (imported) ...[
                Icon(Icons.insert_drive_file_rounded, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The card at the end of "My songs" that opens more files.
class _AddSongsCard extends StatelessWidget {
  const _AddSongsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    return FocusCard(
      width: 130,
      onTap: onTap,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_circle_outline_rounded, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(t.addSongs, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

/// Shown at the top of the home screen until the user adds a song file.
class _AddSongsBanner extends StatelessWidget {
  const _AddSongsBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: FocusCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(children: [
            Icon(Icons.library_music_rounded, size: 34, color: scheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.mySongs, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(t.addSongsHint, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 12),
            Icon(Icons.file_open_rounded, color: scheme.primary),
          ]),
        ),
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        color: glassLow,
        border: Border.all(color: glassBorder, width: 2),
      ),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top_rounded, size: 32, color: Colors.white54),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.white70)),
      ]),
    );
  }
}

class _Action {
  const _Action(this.icon, this.label, this.tint, this.onTap);

  final IconData icon;
  final String label;

  /// The color of the icon and of the tile behind it.
  final Color tint;
  final VoidCallback onTap;
}

/// One of the big cards under the title: an icon and a word.
class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, required this.width});

  final _Action action;
  final double width;

  @override
  Widget build(BuildContext context) {
    return FocusCard(
      width: width,
      height: 56,
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          // The icon sits on a tile in its own color, so the four cards
          // are told apart by color as well as by the word.
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: action.tint.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(action.icon, size: 22, color: action.tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The wide card at the top: one press and the last song plays again.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.song, required this.onTap, this.onLongPress});

  final SongInfo song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: FocusCard(
        onTap: onTap,
        onLongPress: onLongPress,
        color: scheme.primary.withValues(alpha: 0.14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(children: [
            // A glowing play button: the first thing the eye lands on.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary,
                boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.5), blurRadius: 18)],
              ),
              child: Icon(Icons.play_arrow_rounded, size: 30, color: scheme.onPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(t.continueSong, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: scheme.primary)),
                const SizedBox(height: 2),
                Text(
                  t.songTitle(song),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                if (song.artist.isNotEmpty)
                  Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 12),
            _DifficultyChip(song.difficulty),
          ]),
        ),
      ),
    );
  }
}
