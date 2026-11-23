import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_lib;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 语音波形条数（与播放端 VoiceMessageV2.wavesCount 保持一致）
const int _waveCount = 28;

/// V2 语音录音控制器（逻辑移植自原版 RecordingViewModel）
///
/// UI 通过 ListenableBuilder 监听：点击麦克风开始录音，录音中可
/// 取消 / 暂停继续 / 停止并发送。
class VoiceRecorderV2 extends ChangeNotifier {
  AudioRecorder? _audioRecorder;
  Timer? _recorderSubscription;

  Duration duration = Duration.zero;
  final List<double> amplitudeTimeline = [];
  bool isPaused = false;
  String? fileName;

  bool get isRecording => _audioRecorder != null;

  /// 开始录音。无权限时返回 false，由 UI 提示。
  Future<bool> start() async {
    final audioRecorder = _audioRecorder ??= AudioRecorder();
    try {
      if (await audioRecorder.hasPermission() == false) return false;

      final codec = await audioRecorder.isEncoderSupported(AudioEncoder.opus)
          ? AudioEncoder.opus
          : AudioEncoder.aacLc;
      fileName =
          'voice_message_${DateTime.now().millisecondsSinceEpoch}.${codec.fileExtension}';

      final tempDir = await getTemporaryDirectory();
      final filePath = path_lib.join(tempDir.path, fileName);

      await WakelockPlus.enable();

      await audioRecorder.start(
        RecordConfig(
          bitRate: AppSettings.audioRecordingBitRate.value,
          sampleRate: AppSettings.audioRecordingSamplingRate.value,
          numChannels: AppSettings.audioRecordingNumChannels.value,
          autoGain: AppSettings.audioRecordingAutoGain.value,
          echoCancel: AppSettings.audioRecordingEchoCancel.value,
          noiseSuppress: AppSettings.audioRecordingNoiseSuppress.value,
          encoder: codec,
        ),
        path: filePath,
      );

      duration = Duration.zero;
      amplitudeTimeline.clear();
      isPaused = false;
      _subscribe();
      notifyListeners();
      return true;
    } catch (_) {
      _reset();
      return false;
    }
  }

  void _subscribe() {
    _recorderSubscription?.cancel();
    _recorderSubscription =
        Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final recorder = _audioRecorder;
      if (recorder == null) return;
      final amplitude = await recorder.getAmplitude();
      var value = 100 + amplitude.current * 2;
      if (value < 1) value = 1;
      amplitudeTimeline.add(value);
      duration += const Duration(milliseconds: 100);
      notifyListeners();
    });
  }

  /// 放弃录音
  Future<void> cancel() async {
    await _reset();
    notifyListeners();
  }

  Future<void> pause() async {
    await _audioRecorder?.pause();
    _recorderSubscription?.cancel();
    isPaused = true;
    notifyListeners();
  }

  Future<void> resume() async {
    await _audioRecorder?.resume();
    _subscribe();
    isPaused = false;
    notifyListeners();
  }

  /// 停止录音并触发发送
  Future<void> stopAndSend(
    Future<void> Function(
      String path,
      int durationMs,
      List<int> waveform,
      String fileName,
    )
    onSend,
  ) async {
    _recorderSubscription?.cancel();
    final recorder = _audioRecorder;
    final path = await recorder?.stop();
    if (path == null) {
      await _reset();
      notifyListeners();
      return;
    }

    // 压缩波形为固定条数（0-1024），算法同原版
    final step = amplitudeTimeline.length < _waveCount
        ? 1
        : (amplitudeTimeline.length / _waveCount).round();
    final waveform = <int>[];
    for (var i = 0; i < amplitudeTimeline.length; i += step) {
      waveform.add((amplitudeTimeline[i] / 100 * 1024).round());
    }

    final recordDuration = duration.inMilliseconds;
    final recordFileName = fileName!;
    await _reset();
    notifyListeners();

    await onSend(path, recordDuration, waveform, recordFileName);
  }

  Future<void> _reset() async {
    WakelockPlus.disable();
    _recorderSubscription?.cancel();
    await _audioRecorder?.stop();
    _audioRecorder?.dispose();
    _audioRecorder = null;
    fileName = null;
    duration = Duration.zero;
    amplitudeTimeline.clear();
    isPaused = false;
  }

  @override
  Future<void> dispose() async {
    await _reset();
    super.dispose();
  }
}

extension on AudioEncoder {
  String get fileExtension {
    switch (this) {
      case AudioEncoder.aacLc:
      case AudioEncoder.aacEld:
      case AudioEncoder.aacHe:
        return 'm4a';
      case AudioEncoder.opus:
        return 'ogg';
      case AudioEncoder.wav:
        return 'wav';
      case AudioEncoder.amrNb:
      case AudioEncoder.amrWb:
      case AudioEncoder.flac:
      case AudioEncoder.pcm16bits:
        throw UnsupportedError('Not yet used');
    }
  }
}
