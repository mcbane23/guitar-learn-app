import 'package:flutter/material.dart';

import '../app.dart';
import '../data/search.dart';
import '../data/song_repository.dart';
import '../l10n/strings.dart';
import '../models/song.dart';
import 'chords_screen.dart';
import 'common.dart';
import 'free_play_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _query = TextEditingController();
  Difficulty? _difficulty;
  bool _refreshStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_refreshStarted) {
      _refreshStarted = true;
      // Look for new online songs in the background; tell the user only if some arrived.
      final songs = AppServices.of(context).songs;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final (result, count) = await songs.refresh();
        if (!mounted || result != RefreshResult.added) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Strings.of(context).newSongs(count))));
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
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([repo, _query]),
          builder: (context, _) {
            final all = repo.songs;
            final searching = _query.text.trim().isNotEmpty || _difficulty != null;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(context, t)),
                SliverToBoxAdapter(child: _searchBar(context, t)),
                if (searching)
                  _results(context, t, searchSongs(all, _query.text, difficulty: _difficulty))
                else ...[
                  _section(context, t, t.beginner, all.where((s) => s.tags.contains('beginner')).toList(), autofocus: true),
                  _section(context, t, t.kids, all.where((s) => s.tags.contains('kids')).toList()),
                  _section(context, t, t.serbianFolk, all.where((s) => s.tags.contains('serbian-folk')).toList()),
                  _section(context, t, t.allSongs, all),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Strings t) {
    Widget action(IconData icon, String label, Widget Function() page) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FilledButton.tonalIcon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page())),
            icon: Icon(icon),
            label: Text(label),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.music_note_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(t.appTitle, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          Wrap(runSpacing: 8, children: [
            action(Icons.grid_view_rounded, t.chords, () => const ChordsScreen()),
            action(Icons.touch_app_rounded, t.freePlay, () => const FreePlayScreen()),
            action(Icons.settings_rounded, t.settings, () => const SettingsScreen()),
          ]),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context, Strings t) {
    Widget chip(String label, Difficulty? d) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label, style: const TextStyle(fontSize: 16)),
            selected: _difficulty == d,
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
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: t.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(icon: const Icon(Icons.clear), onPressed: _query.clear),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
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

  Widget _section(BuildContext context, Strings t, String title, List<SongInfo> songs, {bool autofocus = false}) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 168,
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
                    itemCount: songs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (context, i) => SongCard(
                      song: songs[i],
                      autofocus: autofocus && i == 0,
                      onTap: () => _open(songs[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, Strings t, List<SongInfo> songs) {
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
          maxCrossAxisExtent: 240,
          mainAxisExtent: 152,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
        ),
        itemCount: songs.length,
        itemBuilder: (context, i) => SongCard(song: songs[i], onTap: () => _open(songs[i])),
      ),
    );
  }
}

const _difficultyColors = {
  Difficulty.easy: [Color(0xFF1E8E5A), Color(0xFF136B43)],
  Difficulty.medium: [Color(0xFF2F6BD8), Color(0xFF1F4CA3)],
  Difficulty.hard: [Color(0xFFB2458F), Color(0xFF7E2D66)],
};

class SongCard extends StatelessWidget {
  const SongCard({super.key, required this.song, required this.onTap, this.autofocus = false});

  final SongInfo song;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final colors = _difficultyColors[song.difficulty]!;
    final stars = switch (song.difficulty) { Difficulty.easy => 1, Difficulty.medium => 2, Difficulty.hard => 3 };
    return FocusCard(
      width: 220,
      autofocus: autofocus,
      onTap: onTap,
      color: colors.last,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                for (var i = 0; i < 3; i++)
                  Icon(i < stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: Colors.white),
                const SizedBox(width: 6),
                Text(t.difficulty(song.difficulty.name), style: const TextStyle(fontSize: 14, color: Colors.white)),
                const Spacer(),
                const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30),
              ]),
              const Spacer(),
              Text(
                t.script(song.titleFor(t.language.songLang)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, height: 1.15),
              ),
              const SizedBox(height: 4),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
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
      width: 220,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.hourglass_top_rounded, size: 36, color: Colors.white54),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 18, color: Colors.white70)),
      ]),
    );
  }
}
