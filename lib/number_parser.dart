import 'dart:math';

class NumberParser {
  // Chinese digit words — includes common ASR homophones
  static const Map<String, double> _cnDigits = {
    '零': 0, '〇': 0, '哦': 0, '噢': 0,
    '一': 1, '幺': 1, '壹': 1,
    '二': 2, '两': 2, '俩': 2,
    '三': 3,
    '四': 4, '是': 4, '事': 4, '室': 4, '市': 4,
    '五': 5,
    '六': 6,
    '七': 7, '期': 7, '起': 7,
    '八': 8, '吧': 8,
    '九': 9, '就': 9, '久': 9,
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

    // Strip spaces so "三 点 一 四" → "三点一四", "3 . 14" → "3.14"
    final compact = text.replaceAll(' ', '');

    // First try Arabic numerals (also handles "3点14" mixed form)
    final arabicPattern = RegExp(r'-?\d+(?:[.,点]\d+)?');
    for (final m in arabicPattern.allMatches(compact)) {
      final s = m.group(0)!.replaceAll(',', '.').replaceAll('点', '.');
      results.add(s);
    }

    if (results.isNotEmpty) return results;

    // Fall back to converting Chinese number words
    final converted = _convertChineseNumbers(compact);
    if (converted != null) results.add(converted);

    return results;
  }

  static String? _convertChineseNumbers(String text) {
    // Handle decimal: 三点四五 → 3.45  (spaces already stripped by caller)
    // Character class also covers common ASR homophones (是≈四, 就≈九, etc.)
    final decimalRe = RegExp(r'([零〇一幺壹二两俩三四五六七八九]+)点([零〇哦噢一幺二两三四是事室市五六七期起八吧九就久]+)');
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
