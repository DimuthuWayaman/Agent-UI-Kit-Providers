import 'package:flutter/material.dart';

import '../theme/agent_colors.dart';

/// A minimal, language-aware syntax highlighter for fenced code blocks.
///
/// This is intentionally a lexer, not a parser: it classifies comments,
/// strings, numbers, keywords, types and call sites. That covers the visual
/// signal developers actually read for, at a tiny fraction of the cost of
/// embedding a real grammar engine — and it degrades gracefully on languages
/// it has no keyword list for.
class SyntaxHighlighter {
  const SyntaxHighlighter._();

  /// Keyword sets per language family. Unknown languages fall back to the
  /// union of common keywords, which still highlights sensibly.
  static const Map<String, Set<String>> _keywords = {
    'dart': {
      'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
      'catch', 'class', 'const', 'continue', 'covariant', 'default',
      'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends',
      'extension', 'external', 'factory', 'false', 'final', 'finally', 'for',
      'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
      'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
      'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
      'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
      'var', 'void', 'when', 'while', 'with', 'yield',
    },
    'javascript': {
      'async', 'await', 'break', 'case', 'catch', 'class', 'const',
      'continue', 'debugger', 'default', 'delete', 'do', 'else', 'export',
      'extends', 'false', 'finally', 'for', 'function', 'if', 'import', 'in',
      'instanceof', 'let', 'new', 'null', 'of', 'return', 'static', 'super',
      'switch', 'this', 'throw', 'true', 'try', 'typeof', 'undefined', 'var',
      'void', 'while', 'with', 'yield',
    },
    'typescript': {
      'any', 'as', 'async', 'await', 'boolean', 'break', 'case', 'catch',
      'class', 'const', 'continue', 'declare', 'default', 'delete', 'do',
      'else', 'enum', 'export', 'extends', 'false', 'finally', 'for',
      'function', 'if', 'implements', 'import', 'in', 'instanceof',
      'interface', 'keyof', 'let', 'namespace', 'never', 'new', 'null',
      'number', 'of', 'private', 'protected', 'public', 'readonly', 'return',
      'satisfies', 'static', 'string', 'super', 'switch', 'this', 'throw',
      'true', 'try', 'type', 'typeof', 'undefined', 'unknown', 'var', 'void',
      'while', 'yield',
    },
    'python': {
      'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
      'def', 'del', 'elif', 'else', 'except', 'False', 'finally', 'for',
      'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'None',
      'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'True', 'try',
      'while', 'with', 'yield',
    },
    'json': {'true', 'false', 'null'},
    'sql': {
      'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set',
      'delete', 'create', 'table', 'alter', 'drop', 'join', 'left', 'right',
      'inner', 'outer', 'on', 'group', 'by', 'order', 'having', 'limit',
      'offset', 'and', 'or', 'not', 'null', 'as', 'distinct', 'union',
    },
    'shell': {
      'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done',
      'case', 'esac', 'function', 'return', 'export', 'local', 'echo', 'cd',
    },
  };

  /// Maps common fence info strings onto a keyword set.
  static const Map<String, String> _aliases = {
    'js': 'javascript',
    'jsx': 'javascript',
    'mjs': 'javascript',
    'node': 'javascript',
    'ts': 'typescript',
    'tsx': 'typescript',
    'py': 'python',
    'python3': 'python',
    'sh': 'shell',
    'bash': 'shell',
    'zsh': 'shell',
    'console': 'shell',
    'postgres': 'sql',
    'mysql': 'sql',
    'yml': 'yaml',
  };

  /// Languages whose comments start with `#` rather than `//`.
  static const Set<String> _hashComment = {
    'python', 'shell', 'yaml', 'ruby', 'toml', 'r', 'perl',
  };

  /// Highlights [code] and returns spans styled with [colors].
  ///
  /// [baseStyle] supplies the font; only colors and the italic flag on
  /// comments are applied on top of it.
  static List<TextSpan> highlight(
    String code,
    String? language,
    AgentSyntaxColors colors,
    TextStyle baseStyle,
  ) {
    final lang = _resolveLanguage(language);
    final keywords = _keywords[lang] ?? _allKeywords;
    final usesHash = _hashComment.contains(lang);

    final spans = <TextSpan>[];
    final buffer = StringBuffer();

    void flushPlain() {
      if (buffer.isNotEmpty) {
        spans.add(
          TextSpan(
            text: buffer.toString(),
            style: baseStyle.copyWith(color: colors.plain),
          ),
        );
        buffer.clear();
      }
    }

    void emit(String text, Color color, {bool italic = false}) {
      flushPlain();
      spans.add(
        TextSpan(
          text: text,
          style: baseStyle.copyWith(
            color: color,
            fontStyle: italic ? FontStyle.italic : null,
          ),
        ),
      );
    }

    var i = 0;
    while (i < code.length) {
      final c = code[i];

      // Line comments.
      if (usesHash && c == '#') {
        final end = _lineEnd(code, i);
        emit(code.substring(i, end), colors.comment, italic: true);
        i = end;
        continue;
      }
      if (!usesHash && c == '/' && i + 1 < code.length) {
        if (code[i + 1] == '/') {
          final end = _lineEnd(code, i);
          emit(code.substring(i, end), colors.comment, italic: true);
          i = end;
          continue;
        }
        if (code[i + 1] == '*') {
          final close = code.indexOf('*/', i + 2);
          final end = close < 0 ? code.length : close + 2;
          emit(code.substring(i, end), colors.comment, italic: true);
          i = end;
          continue;
        }
      }

      // Strings, including triple-quoted forms.
      if (c == '"' || c == "'" || c == '`') {
        final end = _stringEnd(code, i, c);
        emit(code.substring(i, end), colors.string);
        i = end;
        continue;
      }

      // Numbers, including hex and decimals.
      if (_isDigit(c) && (i == 0 || !_isIdentifierChar(code[i - 1]))) {
        var j = i;
        if (c == '0' &&
            i + 1 < code.length &&
            (code[i + 1] == 'x' || code[i + 1] == 'X')) {
          j = i + 2;
          while (j < code.length && _isHexDigit(code[j])) {
            j++;
          }
        } else {
          while (j < code.length &&
              (_isDigit(code[j]) || code[j] == '.' || code[j] == '_')) {
            j++;
          }
        }
        emit(code.substring(i, j), colors.number);
        i = j;
        continue;
      }

      // Identifiers: keyword, type, function call, or plain.
      if (_isIdentifierStart(c)) {
        var j = i;
        while (j < code.length && _isIdentifierChar(code[j])) {
          j++;
        }
        final word = code.substring(i, j);

        if (keywords.contains(word)) {
          emit(word, colors.keyword);
        } else if (_isCallSite(code, j)) {
          emit(word, colors.function);
        } else if (_looksLikeType(word)) {
          emit(word, colors.type);
        } else {
          buffer.write(word);
        }
        i = j;
        continue;
      }

      // Punctuation and operators.
      if (_isPunctuation(c)) {
        emit(c, colors.punctuation);
        i++;
        continue;
      }

      buffer.write(c);
      i++;
    }

    flushPlain();
    return spans;
  }

  static String? _resolveLanguage(String? language) {
    if (language == null) return null;
    final lower = language.toLowerCase().trim();
    return _aliases[lower] ?? lower;
  }

  static final Set<String> _allKeywords =
      _keywords.values.expand((s) => s).toSet();

  static int _lineEnd(String code, int from) {
    final idx = code.indexOf('\n', from);
    return idx < 0 ? code.length : idx;
  }

  /// Finds the end of a string literal, honoring escapes and triple quotes.
  static int _stringEnd(String code, int start, String quote) {
    final triple = code.startsWith(quote * 3, start);
    final delimiter = triple ? quote * 3 : quote;
    var i = start + delimiter.length;
    while (i < code.length) {
      if (code[i] == r'\') {
        i += 2;
        continue;
      }
      if (code.startsWith(delimiter, i)) return i + delimiter.length;
      // An unterminated single-quoted string ends at the line break, which
      // keeps one stray quote from tinting the rest of the block.
      if (!triple && code[i] == '\n') return i;
      i++;
    }
    return code.length;
  }

  static bool _isCallSite(String code, int afterWord) {
    var i = afterWord;
    while (i < code.length && code[i] == ' ') {
      i++;
    }
    return i < code.length && code[i] == '(';
  }

  /// Treats UpperCamelCase identifiers as type names.
  static bool _looksLikeType(String word) {
    if (word.isEmpty) return false;
    final first = word[0];
    return first == first.toUpperCase() &&
        first != first.toLowerCase() &&
        word.length > 1;
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static bool _isHexDigit(String c) {
    final u = c.toLowerCase().codeUnitAt(0);
    return (u >= 0x30 && u <= 0x39) || (u >= 0x61 && u <= 0x66);
  }

  static bool _isIdentifierStart(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) ||
        (u >= 0x61 && u <= 0x7A) ||
        c == '_' ||
        c == r'$';
  }

  static bool _isIdentifierChar(String c) =>
      _isIdentifierStart(c) || _isDigit(c);

  static bool _isPunctuation(String c) => '{}[]()<>;,.:=+-*/%!&|^~?'.contains(c);
}
