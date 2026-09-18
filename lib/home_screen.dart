import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'number_parser.dart';
import 'csv_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  final CsvManager _csv = CsvManager();

  bool _speechReady = false;
  bool _isListening = false;
  String _statusText = '初始化中…';
  String _lastRecognized = '';
  String _toastMsg = '';
  bool _showToast = false;
  Timer? _toastTimer;
  Timer? _silenceTimer;

  // Animation controllers
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _blue = Color(0xFF0071E3);
  static const _green = Color(0xFF34C759);
  static const _red = Color(0xFFFF3B30);
  static const _bg = Color(0xFFF5F5F7);
  static const _card = Color(0xFFFFFFFF);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _pulseCtrl.stop();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() => _statusText = '需要麦克风权限');
      return;
    }
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    setState(() {
      _speechReady = available;
      _statusText = available ? '点击按钮开始录音' : '语音识别不可用';
    });
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      if (_isListening) {
        // Auto-restart for continuous listening
        _startListening();
      }
    }
  }

  void _onSpeechError(dynamic error) {
    if (_isListening) {
      Future.delayed(const Duration(milliseconds: 500), _startListening);
    }
  }

  Future<void> _startListening() async {
    if (!_speechReady || !_isListening) return;
    try {
      await _speech.listen(
        onResult: _onResult,
        localeId: 'zh_CN',
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
        partialResults: false,
      );
    } catch (_) {}
  }

  Future<void> _toggleListening() async {
    HapticFeedback.mediumImpact();
    if (_isListening) {
      setState(() {
        _isListening = false;
        _statusText = '已停止';
      });
      _pulseCtrl.stop();
      _pulseCtrl.reset();
      await _speech.stop();
    } else {
      setState(() {
        _isListening = true;
        _statusText = '正在监听…';
      });
      _pulseCtrl.repeat(reverse: true);
      await _startListening();
    }
  }

  Future<void> _onResult(SpeechRecognitionResult result) async {
    if (!result.finalResult) return;
    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    setState(() => _lastRecognized = text);

    if (NumberParser.isDeleteCommand(text)) {
      final deleted = await _csv.deleteLast();
      if (deleted) {
        HapticFeedback.heavyImpact();
        setState(() {});
        _showToastMsg('已删除上一条');
      } else {
        _showToastMsg('没有可删除的记录');
      }
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
    } else {
      _showToastMsg('未识别到数字');
    }
  }

  void _showToastMsg(String msg) {
    _toastTimer?.cancel();
    setState(() {
      _toastMsg = msg;
      _showToast = true;
    });
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showToast = false);
    });
  }

  Future<void> _shareCSV() async {
    if (_csv.entries.isEmpty) {
      _showToastMsg('还没有数据');
      return;
    }
    final path = await _csv.getSharePath();
    await Share.shareXFiles([XFile(path)], text: '实验数据CSV');
  }

  Future<void> _newSession() async {
    if (_isListening) await _toggleListening();
    await _csv.newSession();
    setState(() => _lastRecognized = '');
    _showToastMsg('已开始新记录');
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _toastTimer?.cancel();
    _silenceTimer?.cancel();
    _speech.cancel();
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
                Text(
                  '语音数据记录',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                ),
                Text(
                  '实验室数据录入助手',
                  style: TextStyle(fontSize: 13, color: Color(0xFF86868B)),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _shareCSV,
            icon: const Icon(Icons.ios_share_rounded, color: _blue),
            tooltip: '分享CSV',
          ),
          IconButton(
            onPressed: _newSession,
            icon: const Icon(Icons.add_circle_outline_rounded, color: _blue),
            tooltip: '新建记录',
          ),
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
            Text(
              '开始说数字',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              '支持："三点四五" "删除" 等',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
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
          time: '${e.timestamp.hour.toString().padLeft(2, '0')}:${e.timestamp.minute.toString().padLeft(2, '0')}:${e.timestamp.second.toString().padLeft(2, '0')}',
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
          // Last recognized text
          if (_lastRecognized.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Icon(Icons.record_voice_over_rounded, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastRecognized,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF1D1D1F)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // Status text
          Text(
            _statusText,
            style: TextStyle(
              fontSize: 14,
              color: _isListening ? _blue : const Color(0xFF86868B),
              fontWeight: _isListening ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 20),
          // Big record button
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _isListening ? _pulseAnim.value : 1.0,
              child: GestureDetector(
                onTap: _speechReady ? _toggleListening : null,
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
      bottom: 140,
      left: 0,
      right: 0,
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
            child: Text(
              _toastMsg,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
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

  const _EntryCard({
    required this.index,
    required this.value,
    required this.time,
    required this.isLatest,
  });

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
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(fontSize: 12, color: Color(0xFF86868B), fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _blue,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '已记录',
                  style: TextStyle(fontSize: 11, color: _green, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                time,
                style: const TextStyle(fontSize: 11, color: Color(0xFF86868B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
