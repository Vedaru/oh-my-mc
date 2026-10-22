import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_mc/core/instance/args.dart';

/// These strings become `Process.start`'s argv with no further quoting, so a
/// split error is a launch failure, not a display bug.
void main() {
  group('parseArgs', () {
    test('splits on whitespace', () {
      expect(parseArgs('-Xmx4G -XX:+UseG1GC'), ['-Xmx4G', '-XX:+UseG1GC']);
    });

    test('keeps a quoted value as one entry', () {
      // The case from PLAN-M6-M9 6.7: the internal space must not split.
      expect(parseArgs('-Dfoo="a b"'), ['-Dfoo=a b']);
      expect(parseArgs("-Dfoo='a b'"), ['-Dfoo=a b']);
    });

    test('an unquoted split is the same input without quotes', () {
      // Pins why quoting exists: strip the quotes and the entry becomes two.
      expect(parseArgs('-Dfoo=a b'), ['-Dfoo=a', 'b']);
    });

    test('empty input is an empty list, not one empty entry', () {
      expect(parseArgs(''), isEmpty);
      expect(parseArgs('   \n\t\n  '), isEmpty);
      expect(parseArgs('\n\n'), isEmpty);
    });

    test('an explicitly quoted empty string is one empty entry', () {
      expect(parseArgs('""'), ['']);
      expect(parseArgs("''"), ['']);
    });

    test('one argument per line is also valid', () {
      expect(parseArgs('-Xmx4G\n-XX:+UseG1GC\n'), ['-Xmx4G', '-XX:+UseG1GC']);
    });

    test('escaped space outside quotes', () {
      expect(parseArgs(r'-Dfoo=a\ b'), ['-Dfoo=a b']);
    });

    test('escaped quote inside double quotes', () {
      expect(parseArgs(r'-Dfoo="say \"hi\""'), ['-Dfoo=say "hi"']);
    });

    test('single quotes make a backslash literal, as in a shell', () {
      expect(parseArgs(r"'-Dfoo=a\nb'"), [r'-Dfoo=a\nb']);
    });

    test('a dangling backslash survives', () {
      // Windows users paste paths; dropping the last character would be worse
      // than keeping a stray backslash.
      expect(parseArgs(r'-Ddir=C:\temp\'), [r'-Ddir=C:\temp\']);
    });

    test('an unclosed quote runs to the end of the line', () {
      expect(parseArgs('-Dfoo="a b'), ['-Dfoo=a b']);
    });

    test('quotes in the middle of a word join', () {
      expect(parseArgs('-Dfoo=ab"c d"e'), ['-Dfoo=abc de']);
    });

    test('tabs separate like spaces', () {
      expect(parseArgs('-Xmx4G\t-XX:+UseG1GC'), ['-Xmx4G', '-XX:+UseG1GC']);
    });
  });

  group('formatArgs', () {
    test('leaves plain arguments alone', () {
      expect(formatArgs(['-Xmx4G', '-XX:+UseG1GC']), '-Xmx4G\n-XX:+UseG1GC');
    });

    test('quotes only when needed', () {
      expect(formatArgs(['a b']), '"a b"');
      expect(formatArgs(['ab']), 'ab');
    });

    test('empty list formats to empty text', () {
      expect(formatArgs(const []), '');
    });
  });

  group('round trip', () {
    test('every awkward argument survives format -> parse', () {
      final cases = [
        '-Xmx4G',
        '-Dfoo=a b',
        'a"b',
        "a'b",
        r'C:\Users\me\game',
        '',
        '-Dmsg=say "hi"',
        '-Dpath=/a/b c/d',
        'trailing ',
        ' leading',
      ];
      expect(parseArgs(formatArgs(cases)), cases);
    });

    test('formatting an empty list and parsing it is empty', () {
      expect(parseArgs(formatArgs(const [])), isEmpty);
    });
  });
}
