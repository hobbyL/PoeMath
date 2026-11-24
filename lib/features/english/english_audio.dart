import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/english_recording_store.dart';
import 'package:poemath/core/services/speech/speech_audio_recorder.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/models/english_course.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/repositories/practice_draft_repository.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

final englishRecordingStoreProvider = Provider(
  (ref) => EnglishRecordingStore(),
);
typedef EnglishAudioKey = (
  String bookId,
  int profileRevision,
  int restoreEpoch,
);
EnglishAudioKey englishAudioKey(String bookId) => (
  bookId,
  ProfileScope.revision,
  HiveBoxes.meta.get('practice_draft_epoch', defaultValue: 0) as int,
);
final englishAudioProvider = ChangeNotifierProvider.autoDispose
    .family<EnglishAudio, EnglishAudioKey>((ref, key) {
      final audio = EnglishAudio(
        bookId: key.$1,
        tts: ref.watch(ttsServiceProvider),
        cache: ref.watch(textbookFileServiceProvider).narrationCache,
        store: ref.watch(englishRecordingStoreProvider),
      );
      return audio;
    });

/// 独立本地音频会话：只用英文系统合成和麦克风，不启动 ASR。
class EnglishAudio extends ChangeNotifier {
  EnglishAudio({
    required this.bookId,
    required this.tts,
    required this.cache,
    required this.store,
    SpeechAudioRecorder Function()? recorderFactory,
    NarrationPlayer Function()? playerFactory,
  }) : _recorderFactory = recorderFactory ?? RecordSpeechAudioRecorder.new,
       _playerFactory = playerFactory ?? AudioplayersNarrationPlayer.new {
    _profiles = ProfileScope.changes.listen((_) => unawaited(stop()));
    _epochs = HiveBoxes.meta
        .watch(key: 'practice_draft_epoch')
        .listen((_) => unawaited(stop()));
  }
  final String bookId;
  final TtsService tts;
  final NarrationAudioCache cache;
  final EnglishRecordingStore store;
  final SpeechAudioRecorder Function() _recorderFactory;
  final NarrationPlayer Function() _playerFactory;
  final profileId = ProfileScope.currentId,
      profileRevision = ProfileScope.revision;
  final _guard = PracticeDraftRepository();
  NarrationSession? _narration;
  NarrationPlayer? _player;
  SpeechAudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  StreamSubscription<dynamic>? _profiles, _epochs;
  BytesBuilder? _pcm;
  Uint8List? _unsaved;
  Timer? _limit;
  bool _disposed = false;
  int _generation = 0, _request = 0;
  String? _savedId;
  bool recording = false, busy = false;
  String message = '';
  bool get hasUnsaved => _unsaved != null;

  void check() {
    _guard.assertCurrent();
    if (_disposed ||
        profileId != ProfileScope.currentId ||
        profileRevision != ProfileScope.revision) {
      throw StateError('学习档案已变化，请重新进入');
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() {
    _request++;
    return _halt();
  }

  Future<void> _halt() async {
    _generation++;
    _limit?.cancel();
    _limit = null;
    final narration = _narration,
        player = _player,
        recorder = _recorder,
        subscription = _subscription;
    _narration = null;
    _player = null;
    _recorder = null;
    _subscription = null;
    _pcm = null;
    recording = false;
    busy = false;
    message = '';
    await narration?.cancel();
    await player?.dispose();
    await subscription?.cancel();
    if (recorder != null) {
      try {
        await recorder.cancel();
      } finally {
        await recorder.dispose();
      }
    }
    _emit();
  }

  Future<bool> speak(
    String text,
    Map<String, String>? voice, {
    double speed = .45,
  }) async {
    final request = ++_request;
    await _halt();
    if (request != _request) return false;
    check();
    if (voice == null ||
        !RegExp(
          r'^en(?:[-_]|$)',
          caseSensitive: false,
        ).hasMatch(voice['locale'] ?? '')) {
      message = '暂无英语音色，可在“英语声音”中选择或安装语音包';
      _emit();
      return false;
    }
    final generation = _generation, done = Completer<bool>();
    busy = true;
    message = '准备英语示范';
    _emit();
    try {
      _narration = tts.startNarration(
        [text],
        bookId: bookId,
        cache: cache,
        systemVoice: voice,
        speechSpeed: speed,
        systemOnly: true,
        onState: (state, _) {
          if (_disposed || generation != _generation) {
            if (!done.isCompleted) done.complete(false);
            return;
          }
          message = switch (state.status) {
            NarrationStatus.playing => '正在播放英语示范',
            NarrationStatus.failed => state.message ?? '英语示范暂时无法播放，请重试',
            NarrationStatus.completed => '示范播放完成',
            NarrationStatus.stopped => '已停止',
            _ => '准备英语示范',
          };
          if ([
            NarrationStatus.failed,
            NarrationStatus.completed,
            NarrationStatus.stopped,
          ].contains(state.status)) {
            if (!done.isCompleted) {
              done.complete(state.status == NarrationStatus.completed);
            }
          }
          _emit();
        },
      );
      final success = await done.future;
      if (generation == _generation) {
        final narration = _narration;
        _narration = null;
        await narration?.cancel();
        if (success) message = '示范播放完成';
      }
      return success;
    } on Object {
      if (generation == _generation) message = '英语示范暂时无法播放，请重试';
      return false;
    } finally {
      if (generation == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  Future<void> startRecording() async {
    final request = ++_request;
    await _halt();
    if (request != _request) return;
    check();
    final generation = _generation, recorder = _recorderFactory();
    _recorder = recorder;
    busy = true;
    message = '准备录音';
    _emit();
    try {
      if (!await recorder.hasPermission()) {
        throw const FormatException('请允许使用麦克风后重试');
      }
      check();
      if (generation != _generation) return;
      final stream = await recorder.startStream();
      check();
      if (generation != _generation) {
        await recorder.cancel();
        return;
      }
      _pcm = BytesBuilder(copy: false);
      _unsaved = null;
      _savedId = null;
      recording = true;
      busy = false;
      message = '正在录音，最长一分钟';
      _subscription = stream.listen(
        (bytes) {
          if (generation != _generation || !recording) return;
          final remaining = EnglishRecordingStore.maxPcmBytes - _pcm!.length;
          _pcm!.add(
            bytes.length <= remaining ? bytes : bytes.sublist(0, remaining),
          );
          if (_pcm!.length >= EnglishRecordingStore.maxPcmBytes) {
            unawaited(finishRecording());
          }
        },
        onError: (Object _) {
          if (generation != _generation) return;
          message = '录音中断，请重试';
          unawaited(stop());
        },
      );
      _limit = Timer(
        const Duration(seconds: 60),
        () => unawaited(finishRecording()),
      );
      _emit();
    } on Object catch (error) {
      if (generation == _generation) {
        await stop();
        message = error is FormatException
            ? error.message.toString()
            : '无法启动录音，请重试';
        _emit();
      }
    }
  }

  Future<void> finishRecording() async {
    if (!recording) return;
    final generation = _generation;
    recording = false;
    busy = true;
    _limit?.cancel();
    _emit();
    try {
      await _recorder?.stop();
      await _subscription?.cancel();
      if (generation != _generation) return;
      _unsaved = _pcm?.takeBytes();
      await _recorder?.dispose();
      _recorder = null;
      _subscription = null;
      _pcm = null;
      message = '录音已结束，请回听并保存';
    } on Object {
      message = '录音未完成，请重新录制';
    } finally {
      if (generation == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  Future<String> saveRecording() async {
    check();
    final pcm = _unsaved;
    if (pcm == null) throw const FormatException('请先录制这一句');
    if (_savedId != null) return _savedId!;
    final id = newEnglishId(), generation = _generation;
    void available() {
      check();
      if (generation != _generation) throw StateError('录音会话已停止');
    }

    await store.save(profileId, id, pcm, available, bookId: bookId);
    available();
    _savedId = id;
    message = '录音已保存在本机';
    _emit();
    return id;
  }

  void acknowledgeRecording() {
    _unsaved = null;
    _savedId = null;
    _emit();
  }

  Future<void> replay({String? id}) async {
    final request = ++_request;
    await _halt();
    if (request != _request) return;
    check();
    final generation = _generation;
    try {
      final path = id == null
          ? null
          : await store.path(profileId, id, bookId: bookId);
      check();
      if (generation != _generation) return;
      if (id != null && path == null) {
        throw const FormatException('这段录音不在本机，文字记录仍保留');
      }
      if (id == null && _unsaved == null) {
        throw const FormatException('还没有可以回听的录音');
      }
      // 未保存段落也使用正确的 WAV 封装，但不发布个人录音文件。
      final player = _playerFactory();
      _player = player;
      busy = true;
      message = '正在回听';
      _emit();
      await player.play(
        NarrationAudio(
          path: path,
          bytes: path == null
              ? EnglishRecordingStore.encodeWav(_unsaved!)
              : null,
          format: 'wav',
        ),
        onStarted: () {},
      );
      if (generation == _generation) message = '回听结束';
    } on Object catch (error) {
      if (generation == _generation) {
        message = error is FormatException
            ? error.message.toString()
            : '回听失败，请重试';
      }
    } finally {
      if (generation == _generation) {
        await _player?.dispose();
        _player = null;
        busy = false;
        _emit();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_profiles?.cancel());
    unawaited(_epochs?.cancel());
    unawaited(stop());
    super.dispose();
  }
}
