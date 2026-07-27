import 'dart:async';
import 'dart:convert';

import 'package:agent_ui_kit_providers/src/providers/sse_utils.dart';
import 'package:flutter_test/flutter_test.dart';

Stream<List<int>> _chunks(List<String> pieces) {
  return Stream.fromIterable(pieces.map(utf8.encode));
}

void main() {
  group('sseDataEvents', () {
    test('dispatches a single-line event on a blank line', () async {
      final events = await sseDataEvents(_chunks(['data: hello\n\n'])).toList();
      expect(events, ['hello']);
    });

    test('joins consecutive data: lines with a newline', () async {
      final events =
          await sseDataEvents(_chunks(['data: line one\ndata: line two\n\n']))
              .toList();
      expect(events, ['line one\nline two']);
    });

    test('is independent of chunk boundaries, including mid-line splits',
        () async {
      const payload = 'data: {"hello":"world"}\n\n';
      final splitPoint = payload.indexOf('"world"');
      final events = await sseDataEvents(_chunks([
        payload.substring(0, splitPoint),
        payload.substring(splitPoint),
      ])).toList();
      expect(events, ['{"hello":"world"}']);
    });

    test('ignores non-data lines', () async {
      final events = await sseDataEvents(_chunks([
        'event: message\nid: 1\ndata: payload\n\n',
      ])).toList();
      expect(events, ['payload']);
    });

    test('dispatches a trailing event with no final blank line', () async {
      final events = await sseDataEvents(_chunks(['data: last'])).toList();
      expect(events, ['last']);
    });

    test('emits nothing for an empty stream', () async {
      final events = await sseDataEvents(_chunks([])).toList();
      expect(events, isEmpty);
    });
  });
}
