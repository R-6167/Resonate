import 'package:flutter_test/flutter_test.dart';

import 'package:resonate/services/playback_authority.dart';

void main() {
  test('automatic playback generation becomes stale after a user command', () {
    final authority = PlaybackAuthority.instance;

    final generation = authority.beginAutomatic('test_automatic_transition');
    expect(authority.isStale(generation), isFalse);

    authority.markExternalUserCommand('normal_player', 'pause');

    expect(authority.isStale(generation), isTrue);
  });

  test('new automatic generation remains current until the next user command', () {
    final authority = PlaybackAuthority.instance;

    authority.markExternalUserCommand('normal_player', 'play');
    final generation = authority.beginAutomatic('test_crossfade');

    expect(authority.isStale(generation), isFalse);

    authority.markExternalUserCommand('normal_player', 'next');

    expect(authority.isStale(generation), isTrue);
  });
}
