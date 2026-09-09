import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

class TtsService extends ChangeNotifier {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final StorageService _storage = StorageService();

  bool _isVoiceEnabled = false;
  String _currentVoice = 'vi-VN-HoaiMyNeural'; // Mặc định Hoài My (Nữ)
  String _currentRate = '+0%';
  bool _isPlaying = false;
  Process? _playerProcess;
  String? _currentTempFile;

  // Queue xử lý stream câu thời gian thực (chunk-by-chunk)
  final List<String> _sentenceQueue = [];
  StringBuffer _streamBuffer = StringBuffer();
  bool _isProcessingQueue = false;

  bool get isVoiceEnabled => _isVoiceEnabled;
  String get currentVoice => _currentVoice;
  String get currentRate => _currentRate;
  bool get isPlaying => _isPlaying;

  static const Map<String, String> vietnameseVoices = {
    'vi-VN-HoaiMyNeural': 'Hoài My (Nữ - Truyền cảm, tự nhiên)',
    'vi-VN-NamMinhNeural': 'Nam Minh (Nam - Trầm ấm, dõng dạc)',
  };

  Future<void> init() async {
    _isVoiceEnabled = await _storage.getVoiceEnabled();
    _currentVoice = await _storage.getVoiceName();
    _currentRate = await _storage.getVoiceRate();
    notifyListeners();
  }

  Future<void> setVoiceEnabled(bool enabled) async {
    _isVoiceEnabled = enabled;
    await _storage.setVoiceEnabled(enabled);
    if (!enabled) {
      await stop();
    }
    notifyListeners();
  }

  Future<void> setVoice(String voice) async {
    _currentVoice = voice;
    await _storage.setVoiceName(voice);
    notifyListeners();
  }

  Future<void> setRate(String rate) async {
    _currentRate = rate;
    await _storage.setVoiceRate(rate);
    notifyListeners();
  }

  /// Khởi tạo một phiên stream đọc mới khi AI bắt đầu trả lời
  void startStreamSession() {
    stop();
    _sentenceQueue.clear();
    _streamBuffer.clear();
  }

  /// Đón từng token từ AI bắn ra, gom thành câu trọn vẹn và nạp vào hàng đợi đọc ngay
  void feedStreamToken(String token) {
    if (!_isVoiceEnabled) return;
    if (token.isEmpty) return;

    _streamBuffer.write(token);
    _extractAndQueueSentences();
  }

  /// Khi stream từ AI kết thúc hoàn toàn
  void finishStreamSession() {
    if (!_isVoiceEnabled) return;

    final remaining = _streamBuffer.toString().trim();
    if (remaining.isNotEmpty) {
      final clean = cleanTextForSpeech(remaining);
      if (clean.isNotEmpty) {
        _sentenceQueue.add(clean);
      }
    }
    _streamBuffer.clear();
    _processNextInQueue();
  }

  /// Tách câu dựa trên dấu chấm, chấm hỏi, chấm than, dấu hai chấm hoặc xuống dòng
  void _extractAndQueueSentences() {
    final text = _streamBuffer.toString();
    // Regex tìm điểm ngắt câu hoàn chỉnh
    final splitRegex = RegExp(r'([.?!:\n]+|\.\s+)');
    final matches = splitRegex.allMatches(text).toList();

    if (matches.isEmpty) return;

    int lastIndex = 0;
    for (final match in matches) {
      final sentenceRaw = text.substring(lastIndex, match.end);
      final clean = cleanTextForSpeech(sentenceRaw);
      if (clean.isNotEmpty && clean.length > 2) {
        _sentenceQueue.add(clean);
      }
      lastIndex = match.end;
    }

    final remainingText = text.substring(lastIndex);
    _streamBuffer = StringBuffer(remainingText);

    _processNextInQueue();
  }

  /// Xử lý phát lần lượt từng câu trong hàng đợi
  Future<void> _processNextInQueue() async {
    if (_isProcessingQueue) return;
    if (_sentenceQueue.isEmpty) return;

    _isProcessingQueue = true;
    while (_sentenceQueue.isNotEmpty) {
      final sentence = _sentenceQueue.removeAt(0);
      await _playSingleSentence(sentence);
    }
    _isProcessingQueue = false;
  }

  Future<void> _playSingleSentence(String sentence) async {
    if (!_isVoiceEnabled && !kIsWeb) return;
    final edgeTtsPath = await _findEdgeTtsPath();
    final playerCmd = await _findAudioPlayer();
    if (edgeTtsPath == null || playerCmd == null) return;

    final tempMp3 = '${Directory.systemTemp.path}/edge_tts_chunk_${DateTime.now().millisecondsSinceEpoch}.mp3';
    _currentTempFile = tempMp3;

    try {
      final genResult = await Process.run(edgeTtsPath, [
        '--text',
        sentence,
        '--voice',
        _currentVoice,
        if (_currentRate != '+0%') ...['--rate', _currentRate],
        '--write-media',
        tempMp3,
      ]);

      if (genResult.exitCode != 0 || !await File(tempMp3).exists()) {
        return;
      }

      _isPlaying = true;
      notifyListeners();

      List<String> playerArgs = [tempMp3];
      if (playerCmd == 'gst-play-1.0') {
        playerArgs = ['--no-interactive', tempMp3];
      }

      final proc = await Process.start(playerCmd, playerArgs);
      _playerProcess = proc;

      await proc.exitCode;
      _playerProcess = null;
    } catch (_) {
    } finally {
      _isPlaying = false;
      notifyListeners();
      try {
        final f = File(tempMp3);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Tiền xử lý văn bản để đọc voice tự nhiên, lọc bỏ cú pháp code markdown rườm rà
  String cleanTextForSpeech(String raw) {
    var text = raw;

    // Thay thế khối mã code dài bằng câu thông báo ngắn
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' [Đoạn mã lệnh kỹ thuật] ');

    // Thay thế inline code `code`
    text = text.replaceAll(RegExp(r'`([^`]+)`'), r'$1');

    // Thay thế liên kết markdown [Tiêu đề](url)
    text = text.replaceAll(RegExp(r'!\[.*?\]\(.*?\)', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\[(.*?)\]\(.*?\)', caseSensitive: false), r'$1');

    // Xóa các ký tự cú pháp markdown: tiêu đề #, in đậm **, nghiêng *, trích dẫn >
    text = text.replaceAll(RegExp(r'^[#>]+\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'[*_~]'), '');

    // Xóa các dòng phân cách bảng biểu |---|---|
    text = text.replaceAll(RegExp(r'\|[-:\s|]+\|'), '');
    text = text.replaceAll('|', ', ');

    // Chuẩn hóa khoảng trắng và dấu ngắt câu
    text = text.replaceAll(RegExp(r'\n+'), '. ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text.trim();
  }

  /// Tìm đường dẫn lệnh edge-tts trên hệ điều hành
  Future<String?> _findEdgeTtsPath() async {
    final candidates = [
      '/home/yenai/.local/bin/edge-tts',
      '/usr/local/bin/edge-tts',
      '/usr/bin/edge-tts',
      'edge-tts',
    ];

    for (final p in candidates) {
      if (p.startsWith('/') && await File(p).exists()) {
        return p;
      }
    }

    try {
      final res = await Process.run('which', ['edge-tts']);
      if (res.exitCode == 0) {
        final path = res.stdout.toString().trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {}

    return null;
  }

  /// Tìm trình phát âm thanh trên Linux (pw-play hoặc gst-play-1.0)
  Future<String?> _findAudioPlayer() async {
    final candidates = ['pw-play', 'gst-play-1.0', 'aplay'];
    for (final cmd in candidates) {
      try {
        final res = await Process.run('which', [cmd]);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          return cmd;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Dừng phát giọng nói ngay lập tức và xóa toàn bộ hàng đợi
  Future<void> stop() async {
    try {
      _sentenceQueue.clear();
      _streamBuffer.clear();
      _isProcessingQueue = false;

      if (_playerProcess != null) {
        _playerProcess!.kill(ProcessSignal.sigterm);
        _playerProcess = null;
      }
      if (_currentTempFile != null) {
        final f = File(_currentTempFile!);
        if (await f.exists()) {
          await f.delete();
        }
        _currentTempFile = null;
      }
    } catch (_) {}
    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
    }
  }

  /// Phát âm thanh câu trả lời bằng edge-tts (cho nghe thử hoặc đọc lại cả đoạn)
  Future<bool> speak(String rawText, {bool ignoreEnabledCheck = false, bool wait = false}) async {
    if (!_isVoiceEnabled && !ignoreEnabledCheck) {
      debugPrint('[TTS] Bỏ qua speak vì voice chưa được bật (isVoiceEnabled = false)');
      return false;
    }

    final clean = cleanTextForSpeech(rawText);
    if (clean.isEmpty) return false;

    // Dừng âm thanh đang phát trước đó nếu có
    await stop();

    if (kIsWeb) {
      // Môi trường Web: không có CLI Process
      return false;
    }

    try {
      final edgeTtsPath = await _findEdgeTtsPath();
      if (edgeTtsPath == null) {
        debugPrint('[TTS] Không tìm thấy lệnh edge-tts');
        return false;
      }

      final playerCmd = await _findAudioPlayer();
      if (playerCmd == null) {
        debugPrint('[TTS] Không tìm thấy trình phát âm thanh (pw-play hoặc gst-play-1.0)');
        return false;
      }

      final tempMp3Path = '${Directory.systemTemp.path}/edge_tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
      _currentTempFile = tempMp3Path;

      // 1. Tạo file audio MP3 bằng edge-tts
      final genResult = await Process.run(edgeTtsPath, [
        '--text',
        clean,
        '--voice',
        _currentVoice,
        if (_currentRate != '+0%') ...['--rate', _currentRate],
        '--write-media',
        tempMp3Path,
      ]);

      if (genResult.exitCode != 0 || !await File(tempMp3Path).exists()) {
        debugPrint('[TTS] Lỗi tạo file audio edge-tts: ${genResult.stderr}');
        return false;
      }

      // 2. Bắt đầu phát âm thanh
      _isPlaying = true;
      notifyListeners();

      List<String> playerArgs = [tempMp3Path];
      if (playerCmd == 'gst-play-1.0') {
        playerArgs = ['--no-interactive', tempMp3Path];
      }

      final proc = await Process.start(playerCmd, playerArgs);
      _playerProcess = proc;

      final onFinished = proc.exitCode.then((_) async {
        if (_playerProcess == proc) {
          _playerProcess = null;
          _isPlaying = false;
          notifyListeners();
          try {
            final f = File(tempMp3Path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      });

      if (wait) {
        await onFinished;
      }

      return true;
    } catch (e) {
      debugPrint('[TTS] Lỗi phát giọng nói: $e');
      await stop();
      return false;
    }
  }
}
