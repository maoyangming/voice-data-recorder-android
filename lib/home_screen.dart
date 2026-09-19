import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:record/record.dart';
import 'number_parser.dart';
import 'csv_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final CsvManager _csv = CsvManager();
  final _vosk = VoskFlutterPlugin.instance();
  final AudioRecorder _recorder = AudioRecorder();

  Model? _model;
  Recognizer? _recognizer;
  bool _modelReady = false;
  bool _isListening = false;
  String _statusText = '加载离线模型中…';
  String _lastRecognized = '';
  String _toastMsg = '';
  bool _showToast = false;
  Timer? _toastTimer;
  StreamSubscription? _audioSub;
  String _lastProcessed = '';

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _blue = Color(0xFF0071E3);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);
  static const _bg = Color(0xFFF5F5F7);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.stop();
    _init();
  }

  Future<void> _init() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() => _statusText = '需要麦克风权限');
      return;
    }
    try {
      setState(() => _statusText = '首次加载离线模型（约20秒）…');
      final modelLoader = ModelLoader();
      final modelPath = await modelLoader.loadFromAssets(
        'assets/vosk-model-small-cn-0.22.zip',
      );
      _model = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
        grammar: [
          '零', '一', '二', '三', '四', '五', '六', '七', '八', '九', '两',
          '十', '百', '千', '万', '亿',
          '点', '负',
          '删除', '撤销', '删掉', '取消', '删了',
          '[unk]',
        ],
      );
      setState(() {
        _modelReady = true;
        _statusText = '点击按钮开始录音';
      });
    } catch (e) {
      setState(() => _statusText = '模型加载失败: $e');
    }
  }

  Future<void> _toggleListening() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_modelReady || _recognizer == null) return;
    setState(() {
      _isListening = true;
      _statusText = '正在监听…';
      _lastProcessed = '';
    });
    _pulseCtrl.repeat(reverse: true);

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _audioSub = stream.listen((data) async {
      final result = await _recognizer!.acceptWaveformBytes(
        Uint8List.fromList(data),
      );
      if (result) {
        final json = await _recognizer!.getResult();
        final text = _parseVoskJson(json);
        if (text.isNotEmpty && text != _lastProcessed) {
          _lastProcessed = text;
          setState(() => _lastRecognized = text);
          await _processText(text);
          _recognizer!.reset();
          _lastProcessed = '';  // allow same value to be recorded again
        }
      } else {
        // Show partial result in UI
        final json = await _recognizer!.getPartialResult();
        final partial = _parseVoskPartial(json);
        if (partial.isNotEmpty) {
          setState(() => _lastRecognized = partial);
        }
      }
    });
  }

  Future<void> _stopListening() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder.stop();

    if (_recognizer != null) {
      final json = await _recognizer!.getFinalResult();
      final text = _parseVoskJson(json);
      if (text.isNotEmpty && text != _lastProcessed) {
        _lastProcessed = text;
        setState(() => _lastRecognized = text);
        await _processText(text);
      }
      _recognizer!.reset();
    }

    setState(() {
      _isListening = false;
      _statusText = '点击按钮开始录音';
    });
    _pulseCtrl.stop();
    _pulseCtrl.reset();
  }

  String _parseVoskJson(String json) {
    final m = RegExp(r'"text"\s*:\s*"([^"]*)"').firstMatch(json);
    return m?.group(1)?.trim() ?? '';
  }

  String _parseVoskPartial(String json) {
    final m = RegExp(r'"partial"\s*:\s*"([^"]*)"').firstMatch(json);
    return m?.group(1)?.trim() ?? '';
  }

  Future<void> _processText(String text) async {
    if (text.isEmpty) return;
    if (NumberParser.isDeleteCommand(text)) {
      final deleted = await _csv.deleteLast();
      HapticFeedback.heavyImpact();
      setState(() {});
      _showToastMsg(deleted ? '已删除上一条' : '没有可删除的记录');
      return;
    }
    final numbers = NumberParser.extractNumbers(text);
    if (numbers.isNotEmpty) {
      for (final n in numbers) {
        await _csv.addEntry(n);
        HapticFeedback.lightImpact();
      }
      setState(() {});
      _showToastMsg('已记录: ${numbers.join(", ")}');
    }
  }

  void _showToastMsg(String msg) {
    _toastTimer?.cancel();
    setState(() { _toastMsg = msg; _showToast = true; });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  Future<void> _shareCSV() async {
    if (_csv.entries.isEmpty) { _showToastMsg('还没有数据'); return; }
    final path = await _csv.getSharePath();
    await Share.shareXFiles([XFile(path)], text: '实验数据CSV');
  }

  Future<void> _newSession() async {
    if (_isListening) await _stopListening();
    await _csv.newSession();
    setState(() => _lastRecognized = '');
    _showToastMsg('已开始新记录');
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _toastTimer?.cancel();
    _audioSub?.cancel();
    _recorder.dispose();
    _recognizer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildEntryList()),
                _buildBottomPanel(),
              ],
            ),
          ),
          if (_showToast) _buildToast(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('语音数据记录',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                Text('离线语音识别 · 无需网络',
                    style: TextStyle(fontSize: 13, color: Color(0xFF86868B))),
              ],
            ),
          ),
          IconButton(onPressed: _shareCSV, icon: const Icon(Icons.ios_share_rounded, color: _blue)),
          IconButton(onPressed: _newSession, icon: const Icon(Icons.add_circle_outline_rounded, color: _blue)),
        ],
      ),
    );
  }

  Widget _buildEntryList() {
    final entries = _csv.entries;
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('开始说数字',
                style: TextStyle(fontSize: 18, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('支持："3.45" "三点四五" "删除" 等',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      reverse: true,
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final idx = entries.length - 1 - i;
        final e = entries[idx];
        return _EntryCard(
          index: idx + 1,
          value: e.value,
          time: '${e.timestamp.hour.toString().padLeft(2, '0')}:'
              '${e.timestamp.minute.toString().padLeft(2, '0')}:'
              '${e.timestamp.second.toString().padLeft(2, '0')}',
          isLatest: idx == entries.length - 1,
        );
      },
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          if (_lastRecognized.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Icon(Icons.record_voice_over_rounded, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_lastRecognized,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1D1D1F)),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 14,
              color: _isListening ? _blue : const Color(0xFF86868B),
              fontWeight: _isListening ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _isListening ? _pulseAnim.value : 1.0,
              child: GestureDetector(
                onTap: _modelReady ? _toggleListening : null,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isListening
                          ? [_red, const Color(0xFFFF6B6B)]
                          : [_blue, const Color(0xFF0A84FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_isListening ? _red : _blue).withOpacity(0.4),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '共记录 ${_csv.entries.length} 条数据',
            style: const TextStyle(fontSize: 12, color: Color(0xFF86868B)),
          ),
        ],
      ),
    );
  }

  Widget _buildToast() {
    return Positioned(
      bottom: 140, left: 0, right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _showToast ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1D1D1F).withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(_toastMsg, style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final int index;
  final String value;
  final String time;
  final bool isLatest;

  const _EntryCard({required this.index, required this.value, required this.time, required this.isLatest});

  static const _blue = Color(0xFF0071E3);
  static const _green = Color(0xFF34C759);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isLatest ? Border.all(color: _blue.withOpacity(0.3), width: 1.5) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isLatest ? 0.08 : 0.04),
            blurRadius: isLatest ? 12 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(8)),
            child: Center(
              child: Text('$index', style: const TextStyle(fontSize: 12, color: Color(0xFF86868B), fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _blue, letterSpacing: -0.5)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _green.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                child: const Text('已记录', style: TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              Text(time, style: const TextStyle(fontSize: 11, color: Color(0xFF86868B))),
            ],
          ),
        ],
      ),
    );
  }
}
