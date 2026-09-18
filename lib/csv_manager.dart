import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class CsvEntry {
  final String value;
  final DateTime timestamp;

  CsvEntry({required this.value, required this.timestamp});
}

class CsvManager {
  static final CsvManager _instance = CsvManager._internal();
  factory CsvManager() => _instance;
  CsvManager._internal();

  final List<CsvEntry> entries = [];
  String? _currentFilePath;

  String get currentFilePath => _currentFilePath ?? '(未开始)';

  Future<String> _getFilePath() async {
    if (_currentFilePath != null) return _currentFilePath!;
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    _currentFilePath = '${dir.path}/实验数据_$dateStr.csv';
    // Write header
    final f = File(_currentFilePath!);
    await f.writeAsString('序号,数值,时间\n');
    return _currentFilePath!;
  }

  Future<void> addEntry(String value) async {
    final entry = CsvEntry(value: value, timestamp: DateTime.now());
    entries.add(entry);
    final path = await _getFilePath();
    final f = File(path);
    final timeStr = DateFormat('HH:mm:ss').format(entry.timestamp);
    await f.writeAsString('${entries.length},$value,$timeStr\n', mode: FileMode.append);
  }

  Future<bool> deleteLast() async {
    if (entries.isEmpty) return false;
    entries.removeLast();
    // Rewrite entire file
    final path = await _getFilePath();
    final f = File(path);
    final buf = StringBuffer('序号,数值,时间\n');
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final timeStr = DateFormat('HH:mm:ss').format(e.timestamp);
      buf.write('${i + 1},${e.value},$timeStr\n');
    }
    await f.writeAsString(buf.toString());
    return true;
  }

  Future<void> newSession() async {
    entries.clear();
    _currentFilePath = null;
  }

  Future<String> getSharePath() async => await _getFilePath();
}
