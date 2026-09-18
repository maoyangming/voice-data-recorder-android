import 'dart:math';

class NumberParser {
  // Chinese digit words
  static const Map<String, double> _cnDigits = {
    '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    '两': 2,
  };

  static const Map<String, int> _cnUnits = {
    '十': 10, '百': 100, '千': 1000, '万': 10000, '亿': 100000000,
  };

  static const List<String> _deleteKeywords = [
    '删除', '撤销', '删掉', '取消', '删了',
  ];

  static bool isDeleteCommand(String text) {
    return _deleteKeywords.any((kw) => text.contains(kw));
  }

  /// Extract numbers from transcribed text.
  /// Returns a list of (value, original_string) pairs.
  static List<String> extractNumbers(String text) {
    final results = <String>[];

    // First try Arabic numerals with optional decimal/negative
    final arabicPattern = RegExp(r'-?\d+(?:[.,]\d+)?');
    for (final m in arabicPattern.allMatches(text)) {
      final s = m.group(0)!.replaceAll(',', '.');
      results.add(s);
    }

    if (results.isNotEmpty) return results;

    // Fall back to converting Chinese number words
    final converted = _convertChineseNumbers(text);
    if (converted != null) results.add(converted);

    return results;
  }

  static String? _convertChineseNumbers(String text) {
    // Handle decimal: 三点四五 → 3.45
    final decimalRe = RegExp(r'([零一二三四五六七八九两]+)点([零一二三四五六七八九]+)');
    final dm = decimalRe.firstMatch(text);
    if (dm != null) {
      final intPart = _chineseToInt(dm.group(1)!);
      final fracPart = dm.group(2)!.split('').map((c) => _cnDigits[c]?.toInt().toString() ?? c).join();
      if (intPart != null) return '$intPart.$fracPart';
    }

    // Plain integer
    final intRe = RegExp(r'[零一二三四五六七八九两十百千万亿]+');
    final im = intRe.firstMatch(text);
    if (im != null) {
      final v = _chineseToInt(im.group(0)!);
      if (v != null) return v.toString();
    }

    return null;
  }

  static int? _chineseToInt(String s) {
    if (s.isEmpty) return null;
    int result = 0;
    int current = 0;

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];
      if (_cnDigits.containsKey(ch)) {
        current = _cnDigits[ch]!.toInt();
      } else if (_cnUnits.containsKey(ch)) {
        final unit = _cnUnits[ch]!;
        if (unit >= 10000) {
          result = (result + current) * unit;
          current = 0;
        } else {
          if (current == 0 && unit == 10) current = 1;
          result += current * unit;
          current = 0;
        }
      }
    }
    result += current;
    return result > 0 ? result : null;
  }
}
