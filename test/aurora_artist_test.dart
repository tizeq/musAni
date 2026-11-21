import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/models.dart';
import 'package:musani/playlists/playlist_repository.dart';
import 'package:musani/settings/settings_controller.dart';
import 'package:musani/ui/artist_page.dart';
import 'package:musani/ui/design_system.dart';

import 'support/library_fakes.dart';

class _PagedArtistRepository extends FakeLibraryRepository {
  _PagedArtistRepository(super.tracks);

  @override
  Future<LibraryResult> query(LibraryQuery query) async {
    queries.add(query);
    expect(query.artistId, 'artist');
    final entries = query.search.isEmpty ? tracks : tracks.take(1);
    return LibraryResult(
      total: entries.length,
      tracks: entries.skip(query.offset).take(query.limit).toList(),
    );
  }
}

void main() {
  testWidgets(
    'artist row uses the visible filter and play all uses the full artist',
    (tester) async {
      final tracks = List.generate(
        121,
        (i) => LibraryTrack(
          id: i,
          path: '/music/$i.flac',
          albumId: null,
          metadata: TrackMetadata(
            title: 'Track $i',
            artists: const ['Artist'],
            album: '',
            albumArtist: '',
          ),
          size: 1,
          modifiedUs: 1,
          changedUs: 1,
        ),
      );
      final repo = _PagedArtistRepository(tracks);
      final library = LibraryController(repo);
      addTearDown(library.dispose);
      LibraryQuery? played;
      String? path;
      await tester.pumpWidget(
        MaterialApp(
          theme: MusaniDesign.theme(MusaniTheme.atmosphere, Brightness.dark),
          home: ArtistPage(
            artist: const LibraryArtist(
              id: 'artist',
              name: 'Artist',
              trackCount: 121,
              albumCount: 0,
            ),
            library: library,
            playlists: PlaylistRepository(repo.directory),
            onPlayQuery: (query, {startPath}) async {
              played = query;
              path = startPath;
            },
            onOpenAlbum: (_) {},
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('artist-aurora-cover'))).height,
        lessThanOrEqualTo(112),
      );
      await tester.enterText(find.byKey(const Key('artist-search')), 'Track 0');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Track 1'), findsNothing);

      repo.queries.clear();
      await tester.tap(find.widgetWithText(ListTile, 'Track 0'));
      await tester.pumpAndSettle();
      expect(played?.artistId, 'artist');
      expect(played?.search, 'Track 0');
      expect(path, tracks.first.path);

      await tester.tap(find.byKey(const Key('artist-play-all')));
      await tester.pumpAndSettle();
      expect(played?.artistId, 'artist');
      expect(played?.search, isEmpty);
      expect(path, isNull);
      expect(repo.queries, isEmpty);
    },
  );
}
