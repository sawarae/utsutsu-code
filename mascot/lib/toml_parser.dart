/// Minimal TOML parser sufficient for parts-model config files.
///
/// Supports:
/// - String values (double-quoted, with basic escapes)
/// - Integer and float values
/// - Boolean values (true / false)
/// - Tables `[section]` and `[section.subsection]`
/// - Arrays of inline tables `[{ key = "val" }, ...]`
/// - Comments starting with `#`
///
/// Does NOT support: multi-line strings, datetime, bare keys with dots
/// inside values, or full TOML spec edge cases.
class TomlParser {
  /// Parse a TOML string and return a nested Map.
  static Map<String, dynamic> parse(String source) {
    final result = <String, dynamic>{};
    var current = result;
    final lines = source.split('\n');

    for (int i = 0; i < lines.length; i++) {
      var line = lines[i].trim();

      // Skip empty lines and comments
      if (line.isEmpty || line.startsWith('#')) continue;

      // Strip inline comments (not inside strings)
      line = _stripInlineComment(line);

      // Table header: [section] or [section.subsection]
      if (line.startsWith('[') && !line.startsWith('[[')) {
        final headerEnd = line.indexOf(']');
        if (headerEnd < 0) continue;
        final path = line.substring(1, headerEnd).trim();
        current = _ensurePath(result, path.split('.'));
        continue;
      }

      // Key = value
      final eqIdx = line.indexOf('=');
      if (eqIdx < 0) continue;

      final key = line.substring(0, eqIdx).trim();
      final rawValue = line.substring(eqIdx + 1).trim();

      // Array value that may span multiple lines
      if (rawValue.startsWith('[')) {
        String arrayStr = rawValue;
        // Collect continuation lines if brackets are not balanced
        while (!_bracketsBalanced(arrayStr) && i + 1 < lines.length) {
          i++;
          var nextLine = lines[i].trim();
          if (nextLine.startsWith('#')) nextLine = '';
          arrayStr += '\n$nextLine';
        }
        current[key] = _parseArray(arrayStr);
      } else {
        current[key] = _parseValue(rawValue);
      }
    }

    return result;
  }

  /// Navigate/create nested maps for a dotted path like `["layers", "Body"]`.
  static Map<String, dynamic> _ensurePath(
      Map<String, dynamic> root, List<String> parts) {
    var node = root;
    for (final part in parts) {
      node = node.putIfAbsent(part, () => <String, dynamic>{})
          as Map<String, dynamic>;
    }
    return node;
  }

  /// Parse a single scalar value.
  static dynamic _parseValue(String raw) {
    if (raw.isEmpty) return '';

    // Quoted string
    if (raw.startsWith('"')) {
      return _parseString(raw);
    }

    // Boolean
    if (raw == 'true') return true;
    if (raw == 'false') return false;

    // Number
    if (raw.contains('.')) {
      final d = double.tryParse(raw);
      if (d != null) return d;
    }
    final n = int.tryParse(raw);
    if (n != null) return n;

    return raw;
  }

  /// Parse a double-quoted string with basic escape support.
  static String _parseString(String raw) {
    // Find the closing quote
    int end = 1;
    final buf = StringBuffer();
    while (end < raw.length) {
      final ch = raw[end];
      if (ch == '\\' && end + 1 < raw.length) {
        final next = raw[end + 1];
        switch (next) {
          case 'n':
            buf.write('\n');
            break;
          case 't':
            buf.write('\t');
            break;
          case '\\':
            buf.write('\\');
            break;
          case '"':
            buf.write('"');
            break;
          default:
            buf.write('\\');
            buf.write(next);
        }
        end += 2;
      } else if (ch == '"') {
        break;
      } else {
        buf.write(ch);
        end++;
      }
    }
    return buf.toString();
  }

  /// Parse an array value: `[item, item, ...]`.
  /// Items can be scalars or inline tables `{ key = "val", ... }`.
  static List<dynamic> _parseArray(String raw) {
    // Strip outer brackets
    final trimmed = raw.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
      return [];
    }
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return [];

    final items = <dynamic>[];
    int pos = 0;

    while (pos < inner.length) {
      // Skip whitespace, newlines, commas
      while (pos < inner.length &&
          (inner[pos] == ' ' ||
              inner[pos] == '\t' ||
              inner[pos] == '\n' ||
              inner[pos] == '\r' ||
              inner[pos] == ',')) {
        pos++;
      }
      if (pos >= inner.length) break;

      // Skip comments
      if (inner[pos] == '#') {
        // Skip to end of line
        while (pos < inner.length && inner[pos] != '\n') {
          pos++;
        }
        continue;
      }

      if (inner[pos] == '{') {
        // Inline table
        final end = _findMatchingBrace(inner, pos);
        final tableStr = inner.substring(pos + 1, end).trim();
        items.add(_parseInlineTable(tableStr));
        pos = end + 1;
      } else {
        // Scalar value — read until comma or end
        final start = pos;
        while (pos < inner.length && inner[pos] != ',' && inner[pos] != '\n') {
          pos++;
        }
        final val = inner.substring(start, pos).trim();
        if (val.isNotEmpty) {
          items.add(_parseValue(val));
        }
      }
    }

    return items;
  }

  /// Parse an inline table: `key = "val", key2 = 123`
  static Map<String, dynamic> _parseInlineTable(String raw) {
    final result = <String, dynamic>{};
    // Split on commas that are not inside quotes
    final pairs = _splitTopLevel(raw, ',');
    for (final pair in pairs) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) continue;
      final eqIdx = trimmed.indexOf('=');
      if (eqIdx < 0) continue;
      final key = trimmed.substring(0, eqIdx).trim();
      final val = trimmed.substring(eqIdx + 1).trim();
      result[key] = _parseValue(val);
    }
    return result;
  }

  /// Split a string by a delimiter, but not inside quoted strings.
  static List<String> _splitTopLevel(String s, String delimiter) {
    final parts = <String>[];
    int start = 0;
    bool inQuote = false;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '"' && (i == 0 || s[i - 1] != '\\')) {
        inQuote = !inQuote;
      }
      if (!inQuote && s[i] == delimiter) {
        parts.add(s.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(s.substring(start));
    return parts;
  }

  /// Find matching closing brace for `{` at position [start].
  static int _findMatchingBrace(String s, int start) {
    int depth = 0;
    bool inQuote = false;
    for (int i = start; i < s.length; i++) {
      if (s[i] == '"' && (i == 0 || s[i - 1] != '\\')) {
        inQuote = !inQuote;
      }
      if (inQuote) continue;
      if (s[i] == '{') depth++;
      if (s[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return s.length - 1;
  }

  /// Check whether brackets `[]` in a string are balanced.
  static bool _bracketsBalanced(String s) {
    int depth = 0;
    bool inQuote = false;
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '"' && (i == 0 || s[i - 1] != '\\')) {
        inQuote = !inQuote;
      }
      if (inQuote) continue;
      if (s[i] == '[') depth++;
      if (s[i] == ']') depth--;
    }
    return depth == 0;
  }

  /// Strip an inline comment from a line (anything after `#` not in a string).
  static String _stripInlineComment(String line) {
    bool inQuote = false;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == '"' && (i == 0 || line[i - 1] != '\\')) {
        inQuote = !inQuote;
      }
      if (!inQuote && line[i] == '#') {
        return line.substring(0, i).trimRight();
      }
    }
    return line;
  }
}
