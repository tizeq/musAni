import 'package:sqlite3/sqlite3.dart';

void dropV6AlbumStorage(Database db) {
  db.execute('''
    DROP VIEW user_album_artists;
    DROP VIEW user_album_tracks;
    DROP VIEW user_album_indexed_tracks;
    DROP TABLE user_album_members;
    DROP INDEX playlists_user_albums;
    ALTER TABLE playlist_entries DROP COLUMN album_disc;
    ALTER TABLE playlists DROP COLUMN album_artist;
    ALTER TABLE playlists DROP COLUMN album_year;
    ALTER TABLE playlists DROP COLUMN album_genre;
    ALTER TABLE playlists DROP COLUMN album_disc;
    ALTER TABLE playlists DROP COLUMN album_sort;
    ALTER TABLE playlists DROP COLUMN album_artist_sort;
    ALTER TABLE playlists DROP COLUMN album_search;
    ALTER TABLE playlists DROP COLUMN album_cover_key;
  ''');
}
