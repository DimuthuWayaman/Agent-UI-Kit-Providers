import 'dart:async';
import 'dart:convert';

/// Decodes a byte stream into successive Server-Sent Events `data:` payloads.
///
/// Implements just enough of the SSE spec for the OpenRouter and Gemini
/// streaming endpoints: consecutive `data:` lines within one event join with
/// `\n`, a blank line dispatches the accumulated event, and `event:`/`id:`/
/// comment lines are ignored. Chunk boundaries from the HTTP layer need not
/// align with line breaks; the underlying `LineSplitter` buffers across them.
Stream<String> sseDataEvents(Stream<List<int>> byteStream) async* {
  var buffer = <String>[];
  final lines = byteStream.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.isEmpty) {
      if (buffer.isNotEmpty) {
        yield buffer.join('\n');
        buffer = [];
      }
      continue;
    }
    if (line.startsWith('data:')) {
      buffer.add(line.length > 5 ? line.substring(5).trimLeft() : '');
    }
  }
  if (buffer.isNotEmpty) yield buffer.join('\n');
}
