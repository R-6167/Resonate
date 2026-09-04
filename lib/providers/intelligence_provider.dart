      final byId = {for (final s in songs) s.id: s};
      final now = DateTime.now();
      final currentHourBucket = now.hour ~/ 3;
      final sessionEvents = events.take(8).toList(growable: false);
      final sessionSongIds = sessionEvents.map((e) => e.songId).toSet();
      final sessionArtistCounts = <String, int>{};
      var recentRank = 0;

      for (final e in events) {
        plays[e.songId] = (plays[e.songId] ?? 0) + 1;
        if (e.completed) completes[e.songId] = (completes[e.songId] ?? 0) + 1;
        if (e.skipped) skips[e.songId] = (skips[e.songId] ?? 0) + 1;
        final song = byId[e.songId];
        final artist = song?.artist.trim();
        if (artist != null && artist.isNotEmpty) artistAffinity[artist] = (artistAffinity[artist] ?? 0) + (e.completed ? 1 : e.skipped ? -.8 : e.completionRatio * .5);
        final age = now.difference(e.startedAt).inHours;
        if (age < 48 && e.startedAt.hour ~/ 3 == currentHourBucket) songHourAffinity[e.songId] = (songHourAffinity[e.songId] ?? 0) + (e.completed ? 1.0 : e.completionRatio * .5);
        if (recentRank < 12) recentSongIds.add(e.songId);
        recentRank++;
      }

      for (final e in sessionEvents) {
        final artist = byId[e.songId]?.artist.trim().toLowerCase() ?? '';
        if (artist.isNotEmpty) sessionArtistCounts[artist] = (sessionArtistCounts[artist] ?? 0) + 1;
      }
      final sessionCompleted = sessionEvents.where((e) => e.completed).length;
      final sessionSkipped = sessionEvents.where((e) => e.skipped).length;
      _sessionCompletion = sessionEvents.isEmpty ? 0.0 : sessionCompleted / sessionEvents.length;
      _sessionArtists
        ..clear()
        ..addAll((sessionArtistCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((entry) => entry.key))
        ..removeWhere((artist) => artist.isEmpty);
      if (sessionEvents.isEmpty) {
        _sessionMode = 'Fresh session';
        _sessionSummary = 'Learning the shape of this listening session.';
      } else if (sessionSkipped >= 3 && sessionSkipped > sessionCompleted) {
        _sessionMode = 'Exploring';
        _sessionSummary = 'You are moving through tracks quickly, so I am widening the search without repeating recent choices.';
      } else if (sessionCompleted >= 3 && sessionCompleted >= sessionSkipped + 2) {
        _sessionMode = 'Familiar flow';
        _sessionSummary = 'The session is settling into a strong flow, so I am favoring signals that already work for you.';
      } else {
        _sessionMode = 'Balanced';
        _sessionSummary = 'The session is mixed, so I am balancing familiar picks with a little exploration.';
      }
