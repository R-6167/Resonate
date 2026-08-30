@@
   // Helper methods
-  Song _songFromMap(Map<String, dynamic> map) {
-    return Song(
-      id: map[columnSongId],
-      title: map[columnSongTitle],
-      artist: map[columnSongArtist] ?? 'Unknown Artist',
-      album: map[columnSongAlbum] ?? 'Unknown Album',
-      filePath: map[columnSongFilePath],
-      duration: Duration(milliseconds: map[columnSongDuration] ?? 0),
-      dateAdded: DateTime.parse(map[columnSongDateAdded]),
-      albumArt: map[columnSongAlbumArt],
-    );
-  }
+  Song _songFromMap(Map<String, dynamic> map) {
+    // Use the Song.fromMap factory for safer parsing and defaults
+    return Song.fromMap(map);
+  }
@@
   Playlist _playlistFromMap(Map<String, dynamic> map) {
     return Playlist(
       id: map[columnPlaylistId],
       name: map[columnPlaylistName],
       songIds: [],
       createdAt: DateTime.parse(map[columnPlaylistCreatedAt]),
       description: map[columnPlaylistDescription],
     );
   }
