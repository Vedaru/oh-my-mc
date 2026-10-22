/// Parses the one-argument-per-line and one-line-with-quotes forms into argv.
///
/// The launcher hands these strings to `Process.start`, which takes a list and
/// does no quoting of its own. That makes this the only place a user's typing
/// becomes argv, so it has to agree with what a user expects from a shell - and
/// a wrong split is not a cosmetic bug: `-Dfoo="a b"` becoming two entries makes
/// the JVM reject the launch with a message about `b`.
///
/// Deliberately *not* a shell parser. No variables, no globs, no backticks, no
/// escaping rules that depend on the platform. Those would make the same saved
/// instance behave differently on Windows and Linux.
library;

/// Splits [source] into argv entries.
///
/// Each non-empty line is parsed independently, so a list of arguments is also
/// valid input - which is what makes a paste from a forum post work. Within a
/// line, whitespace separates entries unless it is inside single or double
/// quotes. Quotes are removed. A backslash escapes only the characters that would
/// otherwise end the argument - whitespace, a quote, or another backslash - and is
/// literal everywhere else. That is deliberately narrower than a shell: `C:\temp`
/// and `-Ddir=C:\temp\` have to survive intact, and under shell rules the `\t`
/// would silently become `t` and the trailing `\` would vanish. Inside single
/// quotes nothing is special, as in a shell.
///
/// Empty lines and blank lines produce no entry: a user who leaves a trailing
/// newline has not added an empty argument. An unclosed quote is tolerated to the
/// end of the line rather than rejected - the alternative is refusing to launch
/// because of a typo in an argument the JVM may not even read.
List<String> parseArgs(String source) {
  final result = <String>[];
  for (final line in source.split('\n')) {
    _parseLine(line, result);
  }
  return result;
}

/// The inverse, one argument per line, for loading a stored list into an editor.
///
/// Quotes only when needed, so the common case (`-Xmx4G`) round-trips unchanged.
/// An argument containing whitespace is double-quoted and its own quotes and
/// backslashes escaped, which is exactly what [_parseLine] undoes.
String formatArgs(List<String> args) => args.map(_quoteIfNeeded).join('\n');

String _quoteIfNeeded(String arg) {
  if (arg.isEmpty) return '""';
  final needsQuotes = arg.runes.any(
    (r) => r == 0x20 || r == 0x09 || r == 0x22 || r == 0x27 || r == 0x5c,
  );
  if (!needsQuotes) return arg;
  final escaped = arg.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

void _parseLine(String line, List<String> out) {
  final buffer = StringBuffer();
  var started = false;
  var inSingle = false;
  var inDouble = false;

  for (var i = 0; i < line.length; i++) {
    final ch = line[i];

    if (inSingle) {
      if (ch == "'") {
        inSingle = false;
      } else {
        buffer.write(ch);
      }
      continue;
    }

    if (ch == r'\') {
      final next = i + 1 < line.length ? line[i + 1] : '';
      final escapable =
          next == '"' ||
          next == r'\' ||
          (!inDouble && (next == ' ' || next == '\t'));
      if (escapable) {
        buffer.write(next);
        i++;
      } else {
        // A Windows path separator, not an escape. Keeping it is the difference
        // between launching and failing with "Class not found".
        buffer.write(ch);
      }
      started = true;
      continue;
    }

    if (inDouble) {
      if (ch == '"') {
        inDouble = false;
      } else {
        buffer.write(ch);
      }
      continue;
    }

    if (ch == '"') {
      inDouble = true;
      // An empty quoted string is a real, empty argument.
      started = true;
    } else if (ch == "'") {
      inSingle = true;
      started = true;
    } else if (ch == ' ' || ch == '\t' || ch == '\r') {
      if (started) {
        out.add(buffer.toString());
        buffer.clear();
        started = false;
      }
    } else {
      buffer.write(ch);
      started = true;
    }
  }

  if (started) out.add(buffer.toString());
}
