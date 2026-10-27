import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Резултат от запис.
class VoiceRecording {
  final String filePath;
  final int durationMs;
  final int sizeBytes;

  const VoiceRecording({
    required this.filePath,
    required this.durationMs,
    required this.sizeBytes,
  });
}

/// Запис на глас (m4a/aac). Без UI.
class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  DateTime? _startedAt;
  String? _path;
  bool _locked = false;

  bool get isRecording => _startedAt != null;
  bool get isLocked => _locked;

  Stream<Duration> get elapsedStream async* {
    while (isRecording) {
      final start = _startedAt;
      if (start == null) break;
      yield DateTime.now().difference(start);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> start() async {
    if (isRecording) return true;
    if (!await ensurePermission()) return false;

    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/criptivo_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _path!,
    );

    _startedAt = DateTime.now();
    _locked = false;
    return true;
  }

  void lock() {
    if (isRecording) _locked = true;
  }

  void unlock() {
    _locked = false;
  }

  /// Спира и връща файла. [cancel] = изтрива, без резултат.
  Future<VoiceRecording?> stop({bool cancel = false}) async {
    if (!isRecording) return null;

    final path = await _recorder.stop();
    final started = _startedAt;
    _startedAt = null;
    _locked = false;

    final filePath = path ?? _path;
    _path = null;

    if (filePath == null) return null;

    final file = File(filePath);
    if (cancel) {
      if (await file.exists()) await file.delete();
      return null;
    }

    if (!await file.exists()) return null;

    final durationMs =
        started != null ? DateTime.now().difference(started).inMilliseconds : 0;
    // Твърде кратко = случайно тапване
    if (durationMs < 400) {
      await file.delete();
      return null;
    }

    final size = await file.length();
    return VoiceRecording(
      filePath: filePath,
      durationMs: durationMs,
      sizeBytes: size,
    );
  }

  Future<void> dispose() async {
    if (isRecording) {
      await stop(cancel: true);
    }
    await _recorder.dispose();
  }
}
