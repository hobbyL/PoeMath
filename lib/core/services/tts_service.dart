// lib/core/services/tts_service.dart
//
// TTS 朗读服务：系统引擎（flutter_tts）+ 可选自建 Worker 云端合成。
// 云端开启且服务已验证时云优先，失败静默回退系统音色，朗读不中断。

import 'dart:async';
import 'package:poemath/core/services/cloud_usage_service.dart';

import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';

import 'package:poemath/core/services/tts/tts_models.dart';
import 'package:poemath/core/services/tts/worker_tts_client.dart';
import 'package:poemath/core/services/tts/narration_audio_cache.dart';
import 'package:poemath/core/services/tts/narration_player.dart';
import 'package:poemath/core/services/tts/narration_session.dart';
import 'package:poemath/core/services/tts/system_tts_file_synthesizer.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

/// 单段朗读结果（云端全跳句检测）。
enum _SegmentPlayResult {
  /// 云端合成成功并完成播放。
  playedCloud,

  /// 系统引擎完成当段（含云端合成失败回退）。
  playedSystem,

  /// 云端合成成功但播放失败，跳过该句（不回退系统，避免双读）。
  skippedCloudPlay,

  /// 未发起播放（stop 抢跑或会话已被新会话接管）。
  notStarted,
}

/// TTS 朗读服务。
///
/// 支持全文朗读、逐句/逐行朗读与音色选择；云端模式逐段合成、
/// 逐段播放，`onLineStart` / `onSentenceStart` 回调时序与系统模式一致。
class TtsService {
  static const String _logTag = 'Tts';

  /// 云端合成内存 LRU 容量（行级 mp3，< 2MB）。
  static const int _cloudCacheCapacity = 32;
  static const int _cloudCacheByteLimit = 8 * 1024 * 1024;
  int _cloudCacheBytes = 0;

  /// 云端全跳句（所有段合成成功但播放均失败）时上抛的异常消息。
  static const String _cloudAllPlaySkippedMessage = '云端音频播放失败，请稍后重试';

  final FlutterTts _tts;
  final SettingsRepository _settings;
  final WorkerTtsClient? _cloudClient;

  CloudAudioPlayer? _cloudPlayer;
  SystemTtsFileSynthesizer? _fileSynthesizer;
  final NarrationPlayer Function()? _narrationPlayerFactory;
  NarrationSession? _narration;
  Future<void>? _narrationRetirement;
  final Map<String, Uint8List> _cloudCache = <String, Uint8List>{};

  WorkerTtsConfig? _cloudConfig;

  /// 鉴权类错误（401）后置位：本次朗读整段降级系统音色，
  /// 避免逐行重复撞错；下次朗读入口重置。
  bool _cloudSessionDisabled = false;

  bool _initialized = false;
  bool _isSpeaking = false;
  String? _engineErrorMessage;

  /// 用户主动停止标志，仅 [stop] 方法设置，
  /// 避免 completionHandler 干扰 [speakLines] 循环。
  bool _stopRequested = false;

  /// 会话代际令牌：新朗读入口 / [stop] / [dispose] 均递增。
  ///
  /// 朗读入口在方法最前（任何 await 之前，含引擎初始化与云端状态刷新
  /// 窗口）递增并捕获本会话代际——入口调用即宣告新会话诞生，窗口内
  /// 的 stop/dispose 递增计数后，本会话首个循环检查即死。在途会话在
  /// 循环迭代与段发起（onReady 触发、`play(bytes)` / `speak(text)`
  /// 发起）前校验，失配即退出——根治「stop 失败后旧循环复活双读」
  /// 「停止后合成返回仍出声的孤儿音频」与「初始化窗口内页面已销毁
  /// resume 后整首照播」三类竞态，不再依赖事件循环时序运气。
  int _sessionGeneration = 0;

  TtsService(
    this._settings, {
    FlutterTts? flutterTts,
    WorkerTtsClient? cloudClient,
    CloudAudioPlayer? cloudPlayer,
    SystemTtsFileSynthesizer? fileSynthesizer,
    NarrationPlayer Function()? narrationPlayerFactory,
  })  : _tts = flutterTts ?? FlutterTts(),
        _cloudClient = cloudClient,
        _cloudPlayer = cloudPlayer,
        _fileSynthesizer = fileSynthesizer,
        _narrationPlayerFactory = narrationPlayerFactory;

  /// 当前是否正在朗读。
  bool get isSpeaking => _isSpeaking;

  /// 当前会话代际令牌。
  ///
  /// 页面用途：朗读回调均携带本会话的 `sessionId`，回调内比对
  /// `sessionId == tts.currentSessionId` 即可判断「我是否仍是当前会话」，
  /// 页面无需自建代际计数器与服务 lockstep 维护（挂账 R3）。
  ///
  /// 页面侧若需在 catch/finally（非回调）中做同样判断，可在入口同步段
  /// 捕获：`final f = tts.speakLines(...); final id = tts.currentSessionId;`
  /// ——朗读入口在任何 await 之前递增令牌，两语句之间无挂起点，读到的
  /// 即本次会话的 id。
  int get currentSessionId => _sessionGeneration;

  /// 云端播放器（懒创建，未注入且从未走云路径时为 null，不触平台通道）。
  CloudAudioPlayer get _cloudPlayerResolved =>
      _cloudPlayer ??= AudioplayersCloudAudioPlayer();

  /// 初始化 TTS 引擎。
  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    await _runEngineOperation('语音引擎初始化失败', () async {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(_settings.ttsSpeed);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      final savedVoice = _settings.ttsVoice;
      if (savedVoice != null) {
        await _tts.setVoice(savedVoice);
      }

      // 该设置决定后续 speak() 的 Future 是否等待朗读完成，
      // 必须在第一次 speak() 之前启用。
      await _tts.awaitSpeakCompletion(true);

      // 引擎层停止源同样递增会话令牌：使「用户 stop / dispose / 引擎
      // 取消 / 引擎错误」四种停止源统一通过令牌机制使在途会话失效，
      // 不再是「令牌机制 + handler 直接置位」两套并行语义（挂账 R2）。
      //
      // 直接置位 `_isSpeaking = false` 保留：被杀会话的 finally 因代际
      // 失配不清位，引擎层兜底防止播放态卡死。
      //
      // 诚实边界：flutter_tts 回调不携带 utterance 身份，晚到的旧会话
      // 取消/错误仍会杀掉新会话——与现状等价（现状的 `_stopRequested`
      // 置位同样会在新会话循环检查处生效），本改动统一语义、消除双机制
      // 漂移，不追求解决回调归属的平台层问题。
      _tts.setCancelHandler(() {
        if (_narration != null) return; // 文件朗读不属于旧系统引擎。
        _sessionGeneration++;
        _isSpeaking = false;
        _stopRequested = true;
      });

      _tts.setErrorHandler((message) {
        if (_narration != null) return;
        _sessionGeneration++;
        _engineErrorMessage = message.toString();
        _isSpeaking = false;
        _stopRequested = true;
      });
    });

    _initialized = true;
  }

  /// 朗读会话入口：刷新云端可用状态（开关 + 自建服务验证）。
  Future<void> _refreshCloudState() async {
    _cloudSessionDisabled = false;
    if (_cloudClient == null || !_settings.ttsCloudEnabled) {
      _cloudConfig = null;
      return;
    }
    try {
      final verified = await _settings.isWorkerTtsVerified();
      _cloudConfig = verified ? await _settings.readWorkerTtsConfig() : null;
    } on Object catch (error) {
      AppLogger.w('读取云端朗读配置失败，本次使用系统音色：$error', tag: _logTag);
      _cloudConfig = null;
    }
  }

  /// 本次会话是否走云端合成。
  bool get _cloudMode =>
      _cloudClient != null && _cloudConfig != null && !_cloudSessionDisabled;

  /// 严格合成：命中缓存或请求云端，异常上抛。
  Future<Uint8List> _synthesizeStrict(String text) async {
    final voice = _settings.ttsCloudVoice;
    final style = _settings.ttsCloudStyle;
    final rate = workerRateFor(_settings.ttsSpeed);
    final cacheKey = '$voice|$style|$rate|$text';
    final cached = _cloudCache.remove(cacheKey);
    if (cached != null) {
      _cloudCache[cacheKey] = cached;
      return cached;
    }

    final generation = _sessionGeneration;
    final bytes = await _cloudClient!.synthesize(
      config: _cloudConfig!,
      text: text,
      voice: voice,
      style: style,
      rate: rate,
    );
    if (generation == _sessionGeneration) _storeCache(cacheKey, bytes);
    return bytes;
  }

  /// 宽松合成：失败返回 null（调用方回退系统音色）。
  ///
  /// 鉴权类错误（401，key 被换/撤销）将本次朗读整段降级。
  Future<Uint8List?> _synthesizeCloud(String text) async {
    if (!_cloudMode) return null;
    try {
      return await _synthesizeStrict(text);
    } on CloudQuotaExceededException {
      _cloudSessionDisabled = true;
      return null;
    } on WorkerTtsException catch (error) {
      if (error.kind == WorkerTtsErrorKind.authentication) {
        _cloudSessionDisabled = true;
      }
      AppLogger.w('云端合成失败，回退系统音色：${error.message}', tag: _logTag);
      return null;
    } on Object catch (error) {
      AppLogger.w('云端合成异常，回退系统音色：$error', tag: _logTag);
      return null;
    }
  }

  void _storeCache(String key, Uint8List bytes) {
    _cloudCacheBytes -= _cloudCache.remove(key)?.length ?? 0;
    if (bytes.length > _cloudCacheByteLimit) return;
    _cloudCache[key] = bytes;
    _cloudCacheBytes += bytes.length;
    while (_cloudCache.length > _cloudCacheCapacity ||
        _cloudCacheBytes > _cloudCacheByteLimit) {
      _cloudCacheBytes -= _cloudCache.remove(_cloudCache.keys.first)!.length;
    }
  }

  /// 单段朗读统一入口：云端优先，失败回退系统引擎完成当段。
  ///
  /// [generation] 为本次朗读会话的代际令牌：在触发 [onFirstReady] 与
  /// 发起 `play(bytes)` / `speak(text)` **之前**校验（合成 await 返回后、
  /// 引擎准备完成后各校验一次），失配或已请求停止则返回
  /// [_SegmentPlayResult.notStarted]——不触发回调、不发起播放，
  /// 消灭「用户已请求停止后合成返回仍完整播出」的孤儿音频。
  ///
  /// [onFirstReady]：该段为本次朗读首段时，在播放动作**发起前**触发一次
  /// （云端在 `play(bytes)` 之前、系统在 `speak(text)` 之前）——语义是
  /// 「首段音频就绪、播放即将开始」，页面遮罩在出声前解除；云端 play
  /// 抛错走「跳过该句」的分支同样已触发（后续行会继续播放，遮罩不允许
  /// 锁死整个会话）。合成/引擎准备异常路径不触发；触发时若已请求停止
  /// （stop 抢跑）或会话已过期不触发。
  Future<_SegmentPlayResult> _speakSegmentBestEffort(
    String text, {
    required int generation,
    void Function()? onFirstReady,
  }) async {
    if (_stopRequested || generation != _sessionGeneration) {
      return _SegmentPlayResult.notStarted;
    }
    if (_cloudMode) {
      final bytes = await _synthesizeCloud(text);
      if (bytes != null) {
        // 合成 await 是长窗口：返回后再次校验代际，stop 抢跑或新会话
        // 接管均不再发起播放（孤儿音频根治点）。
        if (_stopRequested || generation != _sessionGeneration) {
          return _SegmentPlayResult.notStarted;
        }
        // 首段就绪：在播放动作发起前触发，遮罩在出声前解除；
        // play 抛错跳句的分支也已触发，遮罩不会锁死整个会话。
        onFirstReady?.call();
        try {
          await _cloudPlayerResolved.play(bytes);
          return _SegmentPlayResult.playedCloud;
        } on Object catch (error) {
          // 播放失败不回退系统朗读，避免同一句双读。
          AppLogger.w('云端音频播放失败，跳过该句：$error', tag: _logTag);
          return _SegmentPlayResult.skippedCloudPlay;
        }
      }
    }
    var initiated = false;
    // failureMessage 会被页面拼接前缀（如「朗读失败：${message}」），
    // 文案须自成体系且不含前缀字样，避免「朗读失败：朗读失败」式重复。
    await _runEngineOperation('系统语音引擎异常', () async {
      await _tts.setSpeechRate(_settings.ttsSpeed);
      // 播放动作发起前触发（紧随 setSpeechRate、speak 之前）；
      // stop 抢跑或代际失配则整段不发起（含系统路径的孤儿音频守卫）。
      if (_stopRequested || generation != _sessionGeneration) return;
      initiated = true;
      onFirstReady?.call();
      await _tts.speak(text);
      _throwIfEngineReportedError();
    });
    return initiated
        ? _SegmentPlayResult.playedSystem
        : _SegmentPlayResult.notStarted;
  }

  /// 会话是否完整跑完（未被 stop 打断、未被新会话接管）。
  bool _sessionCompleted(int generation) =>
      !_stopRequested && generation == _sessionGeneration;

  /// 云端模式下所有段均「合成成功但播放失败」且段数 > 0。
  ///
  /// `skippedCloudPlay` 只在云路径产生，等价于「云端模式全跳句」；
  /// 部分成功（任一段 playedCloud / playedSystem）保持静默——
  /// 单句跳过是既有容错语义。
  bool _isCloudAllSkipped(List<_SegmentPlayResult> results) =>
      results.isNotEmpty &&
      results.every((result) => result == _SegmentPlayResult.skippedCloudPlay);

  Future<T> _runEngineOperation<T>(
    String failureMessage,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on TtsException {
      rethrow;
    } on Object catch (error) {
      // `on Object` 而非 `on Exception`：操作体内会读 `_settings`（Hive），
      // `HiveError extends Error` 不被 `on Exception` 接住 —— 它会**穿透**
      // 本方法，绕过这里的统一包装，把裸 `HiveError` 抛给页面。下游调用点
      // 普遍按 `TtsException` 分层处理（透传中文 message + 通用兜底），
      // 包装一旦缺失，这些分支全部失效。
      throw TtsException(failureMessage, cause: error);
    }
  }

  void _throwIfEngineReportedError() {
    final message = _engineErrorMessage;
    if (message != null) {
      // 同上：message 会被页面前缀拼接，避免与「朗读失败」字样重复。
      throw TtsException('语音引擎异常：$message');
    }
  }

  /// 获取可用的中文音色列表（已去重）。
  ///
  /// 返回 `List<Map<String, String>>`，每个 Map 至少包含 name 和 locale。
  /// 仅返回 locale 以 "zh" 开头的音色（zh-CN, zh-TW, zh-HK 等）。
  /// 按 name+locale 去重，避免 Android 上返回多个完全相同的条目。
  Future<List<Map<String, String>>> getChineseVoices() async {
    await _ensureInitialized();
    final Object? voices = await _runEngineOperation<Object?>(
      '获取系统音色失败',
      () => _tts.getVoices,
    );
    if (voices is! List<Object?>) {
      throw const TtsException('系统返回了无效的音色数据');
    }

    final seen = <String>{};
    final chineseVoices = <Map<String, String>>[];

    for (final voice in voices) {
      if (voice is! Map<Object?, Object?>) continue;
      final locale = (voice['locale'] ?? '').toString();
      if (!locale.startsWith('zh')) continue;

      final name = (voice['name'] ?? '').toString();
      final key = '$name|$locale';
      if (seen.contains(key)) continue;
      seen.add(key);

      chineseVoices.add({
        'name': name,
        'locale': locale,
      });
    }

    // 按 locale → name 排序，zh-CN 优先
    chineseVoices.sort((a, b) {
      final localeCompare = a['locale']!.compareTo(b['locale']!);
      if (localeCompare != 0) return localeCompare;
      return a['name']!.compareTo(b['name']!);
    });

    return chineseVoices;
  }

  /// 设置系统音色并保存到设置。传 null 恢复系统默认。
  Future<void> setVoice(Map<String, String>? voice) async {
    await _ensureInitialized();
    await _runEngineOperation('设置系统音色失败', () async {
      if (voice != null) {
        await _tts.setVoice(voice);
      } else {
        // 恢复默认：重设语言让系统选择默认音色
        await _tts.setLanguage('zh-CN');
      }
    });
    await _settings.setTtsVoice(voice);
  }

  /// 试听当前音色：朗读一段示例文本（系统音色路径）。
  Future<void> preview(String text) => speak(text);

  /// 云端音色试听：强制走云合成，失败上抛具体原因（设置页展示）。
  Future<void> previewCloud(String text) async {
    final stopping = stop();
    final generation = _sessionGeneration;
    await stopping;
    if (generation != _sessionGeneration) return;
    await _refreshCloudState();
    if (generation != _sessionGeneration) return;
    if (_cloudClient == null || _cloudConfig == null) {
      throw const WorkerTtsException(
        '请先保存并验证自建语音服务',
        kind: WorkerTtsErrorKind.authentication,
      );
    }
    final Uint8List bytes;
    try {
      bytes = await _synthesizeStrict(text);
    } on Object {
      if (generation != _sessionGeneration) return;
      rethrow;
    }
    if (generation != _sessionGeneration) return;
    await _cloudPlayerResolved.play(bytes);
  }

  /// 验证自建服务配置（零成本空 text 探测，不产生真实合成）。
  ///
  /// 设置页专用入口：异常上抛由页面展示具体原因。
  Future<void> verifyCloud(WorkerTtsConfig config) async {
    final client = _cloudClient;
    if (client == null) {
      throw const WorkerTtsException(
        '语音服务客户端不可用',
        kind: WorkerTtsErrorKind.response,
      );
    }
    await client.verify(config);
  }

  /// 拉取云端音色目录（voices 端点无需认证）。
  ///
  /// 地址取自已保存的设置；失败上抛，调用方回退内置精选。
  Future<List<WorkerTtsVoice>> listCloudVoices() async {
    final client = _cloudClient;
    if (client == null) {
      throw const WorkerTtsException(
        '语音服务客户端不可用',
        kind: WorkerTtsErrorKind.response,
      );
    }
    return client.listVoices(
      WorkerTtsClient.normalizeBaseUrl(_settings.ttsCloudBaseUrl),
    );
  }

  /// 朗读文本（全文一次性读完）。
  ///
  /// [onReady] 在首段播放动作发起时触发一次（合成成功后、play/speak 之前，
  /// 缓存命中/系统 TTS 也保证触发）；合成异常或已请求停止时不触发。
  /// 回调携带本次会话的 `sessionId`（见 [currentSessionId]），调用方据此
  /// 判断回调归属，无需自建代际计数器。
  ///
  /// 云端模式下该段「合成成功但播放失败」（全跳句）时上抛 [TtsException]，
  /// 页面按朗读失败提示，不再静默（缺陷 4）。
  Future<void> speak(
    String text, {
    void Function(int sessionId)? onReady,
  }) async {
    final retiring = _retireNarration();
    // 会话令牌在入口同步段捕获（任何 await 之前，含引擎初始化与云端
    // 状态刷新窗口）：入口调用本身即宣告新会话诞生，此后窗口内任何
    // stop/dispose 递增代际都会使本会话在首个段检查即死——消灭
    // 「冷启动初始化窗口内页面已销毁，resume 后整首照播」（缺陷 1）。
    // 停止标志同时复位——新会话自身需在「先 stop 再 speak」流程
    // （如跟读范读切换）后正常运行；旧会话不再因复位而复活。
    final generation = ++_sessionGeneration;
    _stopRequested = false;
    _engineErrorMessage = null;
    _isSpeaking = true;

    try {
      if (retiring != null) {
        await retiring;
        if (generation != _sessionGeneration) return;
      }
      await _ensureInitialized();
      await _refreshCloudState();
      final result = await _speakSegmentBestEffort(
        text,
        generation: generation,
        onFirstReady: onReady == null ? null : () => onReady(generation),
      );
      // 全跳句判定直写（缺陷 6）：单段会话无需构造单元素结果列表，
      // `skippedCloudPlay` 只在云路径产生，等价于「云端模式全跳句」。
      if (_sessionCompleted(generation) &&
          result == _SegmentPlayResult.skippedCloudPlay) {
        throw const TtsException(_cloudAllPlaySkippedMessage);
      }
    } finally {
      // 过期会话不清位（新会话正持有 _isSpeaking），仅当前会话清零。
      if (generation == _sessionGeneration) _isSpeaking = false;
    }
  }

  /// 逐句朗读：按句号、问号、感叹号、中文逗号、换行分割，依次朗读。
  ///
  /// 顿号 `、` **不**作为分割点——词组内停顿会破坏语义（如「李白、杜甫」）。
  ///
  /// [onSentenceStart] 回调：传入当前朗读的句子索引与本次会话 `sessionId`。
  /// [onReady] 在首句播放动作发起时触发一次（speak 之前）；合成异常或
  /// 已请求停止时不触发。
  /// [onComplete] 在全部朗读完毕时调用。
  /// 三个回调均携带 `sessionId`（见 [currentSessionId]）。
  ///
  /// 云端模式下所有句均「合成成功但播放失败」（全跳句）时上抛
  /// [TtsException]（缺陷 4）；部分成功保持静默续播。
  Future<void> speakSentences(
    String text, {
    void Function(int index, int sessionId)? onSentenceStart,
    void Function(int sessionId)? onReady,
    void Function(int sessionId)? onComplete,
  }) async {
    final retiring = _retireNarration();
    // 会话令牌在入口同步段捕获（任何 await 之前，含引擎初始化与云端
    // 状态刷新窗口）：窗口内 stop/dispose 递增代际后，本会话首个循环
    // 检查即死，不再「页面已销毁整首照播」（缺陷 1）。
    final generation = ++_sessionGeneration;
    _stopRequested = false;
    _engineErrorMessage = null;

    // 分割句子（按中文标点和换行）。
    //
    // 中文逗号参与分割（挂账 R1）：译文/赏析等散文长句多为「逗号串句、
    // 句末才有句号」，不拆逗号会让整段一次送入引擎——无朗读停顿，云端
    // 合成长文本也更易失败。实测赏析字段最长段由 p95 45 字 / 最大 111 字
    // 降至 p95 23 字 / 最大 45 字。
    //
    // 英文逗号不纳入：诗词内容为中文语料，正文字段实测几乎不含 `,`
    // （译文/创作背景/名句 0 处），纳入属无收益的行为面扩大。
    // 顿号 `、` 同样不纳入（词组内停顿破坏语义）。
    final sentences = text
        .split(RegExp(r'[。！？，\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    await _runSegments(
      sentences,
      generation: generation,
      retiring: retiring,
      onSegmentStart: onSentenceStart,
      onReady: onReady,
      onComplete: onComplete,
    );
  }

  /// 逐行朗读：调用方提供已拆分的行列表，确保索引与视觉行一一对应。
  ///
  /// [onLineStart] 回调：传入当前朗读的行索引（合成 await 之前触发）与
  /// 本次会话 `sessionId`。
  /// [onReady] 在首行播放动作发起时触发一次（合成成功后、播放之前）；
  /// 合成异常或已请求停止时不触发。
  /// [onComplete] 在全部朗读完毕时调用。
  /// 三个回调均携带 `sessionId`（见 [currentSessionId]）。
  ///
  /// 云端模式下所有行均「合成成功但播放失败」（全跳句）时上抛
  /// [TtsException]（缺陷 4）；部分成功保持静默续播。
  Future<void> speakLines(
    List<String> lines, {
    void Function(int index, int sessionId)? onLineStart,
    void Function(int sessionId)? onReady,
    void Function(int sessionId)? onComplete,
  }) async {
    final retiring = _retireNarration();
    // 会话令牌在入口同步段捕获（任何 await 之前）——语义同
    // [speakSentences]（缺陷 1）。
    final generation = ++_sessionGeneration;
    _stopRequested = false;
    _engineErrorMessage = null;

    await _runSegments(
      lines,
      generation: generation,
      retiring: retiring,
      onSegmentStart: onLineStart,
      onReady: onReady,
      onComplete: onComplete,
    );
  }

  /// speakSentences / speakLines 共享的会话执行体（缺陷 4 抽取）。
  ///
  /// [generation] 由入口在任何 await 之前捕获递增；本方法承载初始化、
  /// 云端状态刷新、逐段循环与全跳句判定等会话尾部逻辑，两个入口只差
  /// 分段来源与回调名。
  Future<void> _runSegments(
    List<String> segments, {
    required int generation,
    Future<void>? retiring,
    void Function(int index, int sessionId)? onSegmentStart,
    void Function(int sessionId)? onReady,
    void Function(int sessionId)? onComplete,
  }) async {
    var completed = false;
    final results = <_SegmentPlayResult>[];
    _isSpeaking = true;
    try {
      if (retiring != null) {
        await retiring;
        if (generation != _sessionGeneration) return;
      }
      await _ensureInitialized();
      await _refreshCloudState();
      for (var i = 0; i < segments.length; i++) {
        if (_stopRequested || generation != _sessionGeneration) break;
        onSegmentStart?.call(i, generation);
        results.add(
          await _speakSegmentBestEffort(
            segments[i],
            generation: generation,
            onFirstReady:
                i == 0 && onReady != null ? () => onReady(generation) : null,
          ),
        );
      }
      completed = _sessionCompleted(generation);
    } finally {
      // 过期会话不清位（新会话正持有 _isSpeaking），仅当前会话清零。
      if (generation == _sessionGeneration) _isSpeaking = false;
    }

    final allSkipped = _isCloudAllSkipped(results);
    if (completed && !allSkipped) onComplete?.call(generation);
    if (completed && allSkipped) {
      throw const TtsException(_cloudAllPlaySkippedMessage);
    }
  }

  /// 停止朗读（云端与系统引擎均停止）。
  Future<void> stop() async {
    _stopRequested = true;
    final cancelling = _retireNarration();
    _cloudClient?.cancelPending();
    // 会话令牌递增：所有在途会话（含引擎 stop 失败后仍挂起的旧循环）
    // 在下一次迭代 / 段发起前按代际退出——即使后续新入口复位
    // `_stopRequested`，旧会话也不会复活（缺陷 1 根治点）。
    _sessionGeneration++;
    // 捕获本次 stop 递增后的代际快照：下方每个平台调用发起前重校验。
    // player.stop() 可挂数百 ms——期间若有新会话入口（或另一次 stop）
    // 递增了代际，则跳过晚到的平台 stop：新会话自身的播放命令会顶掉
    // 旧音频，另一次 stop 已完成平台工作，此处晚到的引擎 stop 反而会
    // 取消新会话当前句、令其静默中断（缺陷 3 根治点）。
    final generation = _sessionGeneration;
    _isSpeaking = false;
    if (cancelling != null) await cancelling;
    final player = _cloudPlayer;
    if (player != null) {
      if (_sessionGeneration != generation) return;
      try {
        await player.stop();
      } on Object catch (error) {
        AppLogger.w('停止云端播放失败（忽略）：$error', tag: _logTag);
      }
    }
    // 页面离开时可能从未启动过引擎；无需触发平台通道。
    if (!_initialized) return;
    // 引擎 stop 发起前的代际重校验（跨过 player.stop 挂起窗口）。
    if (_sessionGeneration != generation) return;
    await _runEngineOperation('停止朗读失败', _tts.stop);
  }

  /// 释放资源。
  void dispose() {
    _stopRequested = true;
    _retireNarration();
    final synthesizer = _fileSynthesizer;
    if (synthesizer != null) {
      unawaited(synthesizer.dispose().catchError((Object _) {}));
    }
    _cloudClient?.cancelPending();
    _cloudCache.clear();
    _cloudCacheBytes = 0;
    _sessionGeneration++; // 使所有在途会话失效。
    _isSpeaking = false;
    final player = _cloudPlayer;
    if (player != null) {
      unawaited(
        player.dispose().then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {},
            ),
      );
    }
    unawaited(
      _tts.stop().then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {},
          ),
    );
  }

  Future<void>? _retireNarration() {
    final narration = _narration;
    _narration = null;
    if (narration != null) {
      final cancelling = narration.cancel().catchError((Object _) {});
      _narrationRetirement = cancelling;
      unawaited(
        cancelling.then((_) {
          if (identical(_narrationRetirement, cancelling)) {
            _narrationRetirement = null;
          }
        }),
      );
    }
    return _narrationRetirement;
  }

  /// 教材长文：首段优先，随后有限预生成，所有音色通过同一文件播放器。
  /// 入口同步分配身份，取消/旧请求均不得启动后续音频。
  NarrationSession startNarration(
    List<String> texts, {
    required String bookId,
    required NarrationAudioCache cache,
    void Function(NarrationState state, int sessionId)? onState,
    void Function(int index, int sessionId)? onSegmentStart,
    void Function(
      int index,
      NarrationAudioIdentity identity,
      int sessionId,
    )? onAudioReady,
  }) {
    final retiring = _retireNarration();
    _cloudClient?.cancelPending();
    final generation = ++_sessionGeneration;
    _stopRequested = false;
    _isSpeaking = true;
    final bookRevision = cache.revision(bookId);
    bool current() =>
        generation == _sessionGeneration &&
        !_stopRequested &&
        cache.revision(bookId) == bookRevision;
    Future<void>? quieting;
    Future<void> quietLegacy() async {
      if (retiring != null) await retiring;
      if (_cloudPlayer != null && current()) await _cloudPlayer!.stop();
      if (_initialized && current()) await _tts.stop();
    }

    final double speed;
    final Map<String, String>? voice;
    final String cloudVoice;
    final String style;
    final bool cloudEnabled;
    try {
      speed = _settings.ttsSpeed;
      voice = _settings.ttsVoice == null
          ? null
          : Map<String, String>.unmodifiable(_settings.ttsVoice!);
      cloudVoice = _settings.ttsCloudVoice;
      style = _settings.ttsCloudStyle;
      cloudEnabled = _settings.ttsCloudEnabled;
    } on Object catch (error) {
      _isSpeaking = false;
      throw TtsException('读取朗读设置失败', cause: error);
    }
    final rate = workerRateFor(speed);
    Future<WorkerTtsConfig?>? configuration;
    Future<String>? systemIdentity;
    var allowCloudRequest = true;
    Future<WorkerTtsConfig?> config() => configuration ??= (() async {
          if (_cloudClient == null || !cloudEnabled) return null;
          try {
            if (!await _settings.isWorkerTtsVerified()) return null;
            return await _settings.readWorkerTtsConfig();
          } on Object {
            return null;
          }
        })();
    Future<NarrationAudio> prepare(int index) async {
      if (!current()) throw const NarrationException('已停止朗读');
      await (quieting ??= quietLegacy());
      if (!current()) throw const NarrationException('已停止朗读');
      final cloud = await config();
      if (!current()) throw const NarrationException('已停止朗读');
      final text = texts[index];
      if (cloud != null) {
        final key = NarrationAudioCache.key([
          1,
          'cloud',
          cloud.base.toString(),
          cloudVoice,
          style,
          rate,
          'mp3',
          text,
        ]);
        final cached = await cache.read(
          bookId,
          key,
          'mp3',
          backend: NarrationBackend.cloud,
        );
        if (cached != null) return cached;
        if (allowCloudRequest && current()) {
          try {
            return await cache.obtain(
              bookId,
              key,
              'mp3',
              backend: NarrationBackend.cloud,
              revision: bookRevision,
              isCurrent: current,
              generate: () {
                if (!current() || !allowCloudRequest) {
                  throw const NarrationException('云端请求已停止');
                }
                return _cloudClient!.synthesize(
                  config: cloud,
                  text: text,
                  voice: cloudVoice,
                  style: style,
                  rate: rate,
                );
              },
            );
          } on CloudQuotaExceededException {
            allowCloudRequest = false;
          } on WorkerTtsException catch (error) {
            if (error.kind == WorkerTtsErrorKind.authentication) {
              allowCloudRequest = false;
            }
          } on NarrationException {/* 缺失段使用系统音色 */}
        }
      }
      if (!current()) throw const NarrationException('已停止朗读');
      final synth = _fileSynthesizer ??= AndroidSystemTtsFileSynthesizer();
      final String identity;
      try {
        identity = await (systemIdentity ??= synth.describeVoice(voice, speed));
      } on Exception {
        systemIdentity = null;
        rethrow;
      }
      if (!current()) throw const NarrationException('已停止朗读');
      final key =
          NarrationAudioCache.key([1, 'system', identity, speed, 'wav', text]);
      return cache.obtain(
        bookId,
        key,
        'wav',
        backend: NarrationBackend.system,
        revision: bookRevision,
        isCurrent: current,
        generate: () {
          if (!current()) throw const NarrationException('已停止朗读');
          return synth.synthesize(
            sessionId: generation,
            text: text,
            voice: voice,
            speed: speed,
          );
        },
      );
    }

    final NarrationPlayer player;
    try {
      player = _narrationPlayerFactory?.call() ?? AudioplayersNarrationPlayer();
    } on Object catch (error) {
      _isSpeaking = false;
      throw TtsException('音频播放器初始化失败', cause: error);
    }
    final session = NarrationSession(
      sessionId: generation,
      count: texts.length,
      player: player,
      isCurrent: current,
      prepare: prepare,
      onState: onState,
      onSegmentStart: onSegmentStart,
      onAudioReady: onAudioReady,
      cancelPreparation: () {
        // 此回调的同步段发生在新请求入口之前；原生按身份单独取消。
        if (generation == _sessionGeneration) _cloudClient?.cancelPending();
        return _fileSynthesizer?.cancelSession(generation) ??
            Future<void>.value();
      },
    );
    _narration = session;
    session.start();
    unawaited(
      session.completed.then<void>(
        (_) {
          if (generation == _sessionGeneration) {
            _isSpeaking = false;
            _narration = null;
          }
        },
        onError: (Object _, StackTrace __) {
          if (generation == _sessionGeneration) {
            _isSpeaking = false;
            _narration = null;
          }
        },
      ),
    );
    return session;
  }
}

/// TTS 引擎初始化或调用失败。
class TtsException implements Exception {
  const TtsException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'TtsException: $message';
}
