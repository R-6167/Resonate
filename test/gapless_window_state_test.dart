import 'package:flutter_test/flutter_test.dart';
import 'package:resonate/playback/gapless_window_state.dart';

void main() {
  group('GaplessWindowState', () {
    test('activates a bounded window and resolves local indices', () {
      final state = GaplessWindowState();

      state.activate(windowStart: 12, ids: ['a', 'b', 'c']);

      expect(state.active, isTrue);
      expect(state.start, 12);
      expect(state.songIds, ['a', 'b', 'c']);
      expect(state.localIndexOf('b'), 1);
      expect(state.localIndexOf('missing'), -1);
    });

    test('reset disables the source and clears ids without changing start', () {
      final state = GaplessWindowState();
      state.activate(windowStart: 4, ids: ['x', 'y']);

      state.reset();

      expect(state.active, isFalse);
      expect(state.songIds, isEmpty);
      expect(state.start, 4);
    });

    test('copies ids so caller mutations cannot change window ownership', () {
      final state = GaplessWindowState();
      final ids = ['first', 'second'];

      state.activate(windowStart: 0, ids: ids);
      ids.add('third');

      expect(state.songIds, ['first', 'second']);
    });
  });
}
