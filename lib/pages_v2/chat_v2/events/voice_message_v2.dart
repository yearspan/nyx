import 'dart:async';
import 'dart:io';

import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets_v2/upload_progress.dart';
import 'package:fluffychat/widgets_v2/v2_toast.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:ogg_caf_converter/ogg_caf_converter.dart';
import 'package:path_provider/path_provider.dart';

/// 语音消息内容（播放按钮 + 波形），背景/时间/时长由 MessageBubbleV2 统一处理。
///
/// 播放逻辑移植自原版 AudioPlayerWidget：下载并解密附件、iOS 上将
/// OGG 转为 CAF、全局只允许一条语音在播放。
class VoiceMessageV2 extends StatefulWidget {
  final Event event;
  final bool isMine;

  const VoiceMessageV2({super.key, required this.event, required this.isMine});

  @override
  State<VoiceMessageV2> createState() => _VoiceMessageV2State();
}

/// 下载状态
enum _VoiceStatus { notDownloaded, downloading, downloaded }

class _VoiceMessageV2State extends State<VoiceMessageV2> {
  static const int wavesCount = 28;

  /// 全局共享：同一时刻只有一条语音在播放
  static AudioPlayer? _sharedPlayer;
  static String? _playingEventId;
  static final ValueNotifier<String?> playingEvent = ValueNotifier(null);

  _VoiceStatus _status = _VoiceStatus.notDownloaded;
  double? _downloadProgress;
  List<int>? _waveform;
  int? _durationMs;
  int _maxWaveForm = 1024;

  StreamSubscription<void>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool get _isActive => _playingEventId == widget.event.eventId;

  @override
  void initState() {
    super.initState();
    _waveform = _readWaveform();
    _durationMs = _readDurationMs();
  }

  /// 语音总时长（毫秒）：优先 info.duration，回退 MSC1767 字段
  int? _readDurationMs() {
    final info = widget.event.content.tryGetMap<String, Object?>('info');
    var ms = info?.tryGet<int>('duration') ?? 0;
    if (ms <= 0) {
      ms =
          widget.event.content
              .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
              ?.tryGet<int>('duration') ??
          0;
    }
    return ms > 0 ? ms : null;
  }

  String get _durationLabel {
    final ms = _durationMs;
    if (ms == null) return '';
    final totalSeconds = (ms / 1000).round();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  /// 解析事件中的波形并归一化到 [wavesCount] 条（0-1024 / 0-256 自适应）
  List<int>? _readWaveform() {
    final eventWaveForm = widget.event.content
        .tryGetMap<String, Object?>('org.matrix.msc1767.audio')
        ?.tryGetList<int>('waveform');
    if (eventWaveForm == null || eventWaveForm.isEmpty) return null;

    // 新版 MSC 最大值为 256（Element X 仍用 1024）
    if (!eventWaveForm.any((value) => value > 256)) {
      _maxWaveForm = 256;
    }

    // 插值扩充到不少于 wavesCount 条
    while (eventWaveForm.length < wavesCount) {
      for (var i = 0; i < eventWaveForm.length; i = i + 2) {
        eventWaveForm.insert(i, eventWaveForm[i]);
      }
    }
    // 抽样/删减到恰好 wavesCount 条
    final step = (eventWaveForm.length / wavesCount).round();
    var i = 0;
    while (eventWaveForm.length > wavesCount) {
      eventWaveForm.removeAt(i);
      i = (i + step) % wavesCount;
    }
    return eventWaveForm
        .map((v) => v > _maxWaveForm ? _maxWaveForm : v)
        .toList();
  }

  Future<void> _onButtonTap() async {
    final player = _isActive ? _sharedPlayer : null;

    // 已在播放本条：播放/暂停/重播
    if (player != null) {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
        await player.play();
        return;
      }
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }

    // 播放新的一条：先停掉旧的
    _positionSub?.cancel();
    _stateSub?.cancel();
    _sharedPlayer
      ?..stop()
      ..dispose();
    _sharedPlayer = null;

    setState(() => _status = _VoiceStatus.downloading);

    File? file;
    MatrixFile? matrixFile;
    try {
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      matrixFile = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize != null && fileSize > 0
            ? (progress) {
                final percentage = progress / fileSize;
                if (mounted) {
                  setState(() {
                    _downloadProgress = percentage < 1 ? percentage : null;
                  });
                }
              }
            : null,
      );

      final attachmentUrl = widget.event.attachmentOrThumbnailMxcUrl();
      if (attachmentUrl != null) {
        final tempDir = await getTemporaryDirectory();
        final fileName = Uri.encodeComponent(attachmentUrl.pathSegments.last);
        file = File('${tempDir.path}/${fileName}_${matrixFile.name}');
        await file.writeAsBytes(matrixFile.bytes);

        // iOS 不支持直接播 OGG，转 CAF
        if (Platform.isIOS &&
            matrixFile.mimeType.toLowerCase() == 'audio/ogg') {
          final convertedFile = File('${file.path}.caf');
          if (!await convertedFile.exists()) {
            await OggCafConverter().convertOggToCaf(
              input: file.path,
              output: convertedFile.path,
            );
          }
          file = convertedFile;
        }
      }

      if (!mounted) return;
      setState(() => _status = _VoiceStatus.downloaded);
    } catch (e) {
      if (mounted) {
        setState(() => _status = _VoiceStatus.notDownloaded);
        V2Toast.show(e.toLocalizedString(context));
      }
      return;
    }

    final audioPlayer = _sharedPlayer = AudioPlayer();
    _playingEventId = widget.event.eventId;
    playingEvent.value = widget.event.eventId;

    if (file != null) {
      await audioPlayer.setFilePath(file.path);
    } else {
      await audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.dataFromBytes(matrixFile.bytes, mimeType: matrixFile.mimeType),
        ),
      );
    }

    _positionSub = audioPlayer.positionStream.listen((_) {
      if (mounted && _isActive) setState(() {});
    });
    _stateSub = audioPlayer.playerStateStream.listen((_) {
      if (mounted && _isActive) setState(() {});
    });

    await audioPlayer.play();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isMine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final waveform = _waveform;

    return ValueListenableBuilder<String?>(
      valueListenable: playingEvent,
      builder: (context, activeEventId, _) {
        final active = activeEventId == widget.event.eventId;
        final player = active ? _sharedPlayer : null;

        final maxPosition = player?.duration?.inMilliseconds.toDouble() ?? 1.0;
        var currentPosition = player?.position.inMilliseconds.toDouble() ?? 0.0;
        if (currentPosition > maxPosition) currentPosition = maxPosition;
        final wavePosition = (currentPosition / maxPosition) * wavesCount;
        final isPlaying =
            player != null &&
            player.playing &&
            player.processingState != ProcessingState.completed;

        return SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 发送中/播放/暂停/下载中
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: widget.event.status.isSending
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: UploadProgressCircle(
                              eventId: widget.event.eventId,
                              size: 20,
                              strokeWidth: 2,
                              color: textColor,
                            ),
                          )
                        : _status == _VoiceStatus.downloading
                        ? Padding(
                            padding: const EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: textColor,
                              value: _downloadProgress,
                            ),
                          )
                        : GestureDetector(
                            onTap: _onButtonTap,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: textColor.withValues(
                                  alpha: isPlaying ? 0.25 : 0.15,
                                ),
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: textColor,
                                size: 20,
                              ),
                            ),
                          ),
                  ),
                  SizedBox(width: 8),
                  // 波形（已播放部分高亮，可点击/拖动定位）
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) => _seekByTap(details, context),
                      child: Row(
                        children: List.generate(wavesCount, (i) {
                          final ratio = waveform == null
                              ? 0.4
                              : waveform[i] / _maxWaveForm;
                          final barHeight = 6 + 20 * ratio;
                          final played = i < wavePosition;
                          return Expanded(
                            child: Center(
                              child: Container(
                                margin: EdgeInsets.symmetric(horizontal: 1),
                                height: barHeight.clamp(3.0, 26.0),
                                decoration: BoxDecoration(
                                  color: played
                                      ? textColor
                                      : textColor.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  // 总时长（与波形同一行）
                  SizedBox(
                    width: 36,
                    child: Text(
                      _durationLabel,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ),
              // 发送中：底部线性上传进度（仅 macOS/iOS 展示真实进度；
              // 其余平台不显示进度条，仅保留播放位的不确定转圈）
              if (widget.event.status.isSending &&
                  PlatformInfos.isMacOSOrIOS) ...[
                const SizedBox(height: 8),
                UploadProgressBuilder(
                  eventId: widget.event.eventId,
                  builder: (context, progress) => ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: textColor.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(textColor),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 点击波形按比例跳转播放进度（未下载时先触发下载播放）
  Future<void> _seekByTap(TapDownDetails details, BuildContext context) async {
    final player = _isActive ? _sharedPlayer : null;
    final duration = player?.duration;
    if (player == null || duration == null) {
      await _onButtonTap();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    final ratio = (details.localPosition.dx / width).clamp(0.0, 1.0);
    await player.seek(
      Duration(milliseconds: (duration.inMilliseconds * ratio).round()),
    );
  }
}
