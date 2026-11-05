// lib/features/profile/speech_recognition_settings_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/speech/preferred_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/services/speech/tencent_speech_recognition_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class SpeechRecognitionSettingsPage extends ConsumerStatefulWidget {
  const SpeechRecognitionSettingsPage({super.key});

  @override
  ConsumerState<SpeechRecognitionSettingsPage> createState() =>
      _SpeechRecognitionSettingsPageState();
}

class _SpeechRecognitionSettingsPageState
    extends ConsumerState<SpeechRecognitionSettingsPage> {
  static const String _testPhrase = '床前明月光';

  late final TextEditingController _secretIdController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _appIdController;
  String _storedAppId = '';
  SpeechRecognitionSettingsState _settings =
      const SpeechRecognitionSettingsState(
    hasCredentials: false,
    isVerified: false,
  );
  bool _loadingSettings = true;
  bool _obscureSecretKey = true;
  bool _showRealtimeSettings = false;
  bool _busy = false;
  bool _recording = false;
  String? _message;
  bool _messageIsError = false;
  Timer? _recordingTimer;
  StreamSubscription<String>? _transcriptSubscription;
  String _liveText = '';
  bool _usedSentenceFallback = false;
  bool _hasTestResult = false;
  int _testGeneration = 0;
  late final SpeechRecognitionService _speechService;

  @override
  void initState() {
    super.initState();
    _secretIdController = TextEditingController();
    _secretKeyController = TextEditingController();
    _appIdController = TextEditingController();
    _speechService = ref.read(speechRecognitionServiceFactoryProvider)();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepositoryProvider);
    try {
      final snapshot = await repo.loadSpeechRecognitionSettingsSnapshot();
      if (!mounted) return;
      _secretIdController.text = snapshot.credentials?.secretId ?? '';
      _secretKeyController.text = snapshot.credentials?.secretKey ?? '';
      _appIdController.text = snapshot.credentials?.appId ?? '';
      _storedAppId = snapshot.credentials?.appId ?? '';
      setState(() {
        _settings = snapshot.settings;
        _showRealtimeSettings = _storedAppId.isNotEmpty;
        _loadingSettings = false;
      });
    } on Object catch (error) {
      AppLogger.e(
        '读取语音识别设置失败',
        tag: 'Speech',
        error: error,
      );
      if (!mounted) return;
      _secretIdController.clear();
      _secretKeyController.clear();
      setState(() {
        _settings = const SpeechRecognitionSettingsState(
          hasCredentials: false,
          isVerified: false,
        );
        _loadingSettings = false;
        _message = '读取本地密钥失败，请重新输入';
        _messageIsError = true;
      });
    }
  }

  TencentAsrCredentials? _readFormCredentials() {
    final credentials = TencentAsrCredentials(
      secretId: _secretIdController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      appId: _appIdController.text.trim(),
    );
    if (!credentials.isComplete) return null;
    return credentials;
  }

  Future<TencentAsrCredentials?> _saveFormCredentials() async {
    final credentials = _readFormCredentials();
    if (credentials == null) {
      _showMessage('请填写 SecretId 和 SecretKey', isError: true);
      return null;
    }
    await ref.read(settingsRepositoryProvider).saveTencentAsrCredentials(
          secretId: credentials.secretId,
          secretKey: credentials.secretKey,
        );
    if (credentials.appId.isNotEmpty || _storedAppId.isNotEmpty) {
      await ref
          .read(settingsRepositoryProvider)
          .saveTencentAsrAppId(credentials.appId);
      _storedAppId = credentials.appId;
    }
    return credentials;
  }

  Future<void> _saveCredentials() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _liveText = '';
      _usedSentenceFallback = false;
      _hasTestResult = false;
    });
    try {
      final credentials = await _saveFormCredentials();
      if (credentials == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _loadSettings();
      if (mounted) {
        _showMessage(
          _settings.isVerified ? '密钥已保存，认字与跟读均可用' : '密钥已保存，认字已可用；跟读需完成录音测试',
        );
      }
    } on Object {
      if (mounted) _showMessage('密钥保存失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTest() async {
    if (_busy || _recording) return;
    final generation = ++_testGeneration;
    setState(() {
      _busy = true;
      _message = null;
      _liveText = '';
      _usedSentenceFallback = false;
      _hasTestResult = false;
    });
    try {
      final credentials = await _saveFormCredentials();
      if (credentials == null || !mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _speechService.initialize();
      if (!mounted) return;
      _stopTranscriptUpdates();
      final speech = _speechService;
      if (speech is StreamingSpeechRecognitionService) {
        _transcriptSubscription = (speech as StreamingSpeechRecognitionService)
            .transcriptStream
            .listen((text) {
              if (mounted && generation == _testGeneration) {
                setState(() => _liveText = text);
              }
            });
      }
      await _speechService.start();
      if (!mounted) {
        await _speechService.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _busy = false;
        _message = '请朗读：$_testPhrase';
        _usedSentenceFallback =
            speech is StreamingSpeechRecognitionService &&
            (speech as StreamingSpeechRecognitionService).usedFallback;
      });
      _recordingTimer = Timer(const Duration(seconds: 15), _finishTest);
    } on SpeechPermissionDeniedException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
      if (mounted) setState(() => _busy = false);
    } on SpeechRecognitionException catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
      if (mounted) setState(() => _busy = false);
    } on Object {
      if (mounted) _showMessage('无法开始录音，请检查麦克风权限', isError: true);
      if (mounted) setState(() => _busy = false);
    } finally {
      if (!mounted || !_recording) _stopTranscriptUpdates();
    }
  }

  Future<void> _finishTest() async {
    if (!_recording) return;
    final repo = ref.read(settingsRepositoryProvider);
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final credentials = _readFormCredentials();
    setState(() {
      _recording = false;
      _busy = true;
      _message = '正在验证腾讯云识别…';
    });
    try {
      if (credentials == null) {
        throw const SpeechRecognitionException('腾讯云密钥已被清空');
      }
      final result = await _speechService.stop();
      if (!mounted) return;
      _stopTranscriptUpdates();
      if (result.text.trim().isEmpty) {
        throw const SpeechRecognitionException('测试未返回文字，请重新朗读');
      }
      setState(() {
        _liveText = result.text;
        _hasTestResult = true;
        _usedSentenceFallback = result.usedFallback;
      });
      await repo.markTencentAsrCredentialsVerified(
        testedCredentials: credentials,
      );
      if (!mounted) return;
      await _loadSettings();
      if (mounted) {
        _showMessage(
          result.text.isEmpty ? '测试未返回文字' : '测试成功，跟读评分已可用',
        );
      }
    } on TencentAsrException catch (error) {
      if (!mounted) return;
      await _invalidateAfterFailedTest();
      if (mounted) _showMessage(error.message, isError: true);
    } on SpeechRecognitionException catch (error) {
      if (!mounted) return;
      await _invalidateAfterFailedTest();
      if (mounted) _showMessage(error.message, isError: true);
    } on Object {
      if (!mounted) return;
      await _invalidateAfterFailedTest();
      if (mounted) _showMessage('测试失败，请检查网络后重试', isError: true);
    } finally {
      _stopTranscriptUpdates();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stopTranscriptUpdates() {
    final subscription = _transcriptSubscription;
    _transcriptSubscription = null;
    unawaited(subscription?.cancel());
  }

  Future<void> _invalidateAfterFailedTest() async {
    if (!mounted) return;
    await ref
        .read(settingsRepositoryProvider)
        .invalidateTencentAsrVerification();
    if (mounted) {
      final settings = await ref
          .read(settingsRepositoryProvider)
          .loadSpeechRecognitionSettings();
      if (mounted) setState(() => _settings = settings);
    }
  }

  Future<void> _cancelTest() async {
    if (!_recording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    ++_testGeneration;
    _stopTranscriptUpdates();
    setState(() {
      _recording = false;
      _busy = true;
      _liveText = '';
      _usedSentenceFallback = false;
    });
    await _speechService.cancel();
    await _invalidateAfterFailedTest();
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = false;
      });
      _showMessage('测试已取消', isError: true);
    }
  }

  Future<void> _deleteCredentials() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _liveText = '';
      _usedSentenceFallback = false;
      _hasTestResult = false;
    });
    try {
      await ref.read(settingsRepositoryProvider).deleteTencentAsrCredentials();
      if (!mounted) return;
      _secretIdController.clear();
      _secretKeyController.clear();
      await _loadSettings();
      if (mounted) _showMessage('腾讯云密钥已删除，跟读需重新配置');
    } on Object {
      if (mounted) _showMessage('删除密钥失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = isError;
      if (isError && !_recording) {
        _liveText = '';
        _usedSentenceFallback = false;
        _hasTestResult = false;
      }
    });
  }

  @override
  void dispose() {
    ++_testGeneration;
    _recordingTimer?.cancel();
    _stopTranscriptUpdates();
    unawaited(_speechService.dispose());
    _secretIdController.dispose();
    _secretKeyController.dispose();
    _appIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    final statusColor =
        _messageIsError ? theme.colorScheme.error : theme.colorScheme.primary;
    final testButtonLabel = _recording ? '结束并验证' : '开始真实录音测试';

    return Scaffold(
      appBar: AppBar(
        title: const Text('语音识别设置'),
        actions: [
          IconButton(
            onPressed: _loadingSettings || _busy || _recording
                ? null
                : _deleteCredentials,
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除腾讯云密钥',
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.all(SpacingTokens.lg),
          children: <Widget>[
            Text('腾讯云密钥', style: theme.textTheme.titleMedium),
            if (_loadingSettings) ...[
              const SizedBox(height: SpacingTokens.sm),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: SpacingTokens.sm),
            TextField(
              controller: _secretIdController,
              enabled: !_loadingSettings && !_busy && !_recording,
              decoration: const InputDecoration(
                labelText: 'SecretId (AK)',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: SpacingTokens.sm),
            TextField(
              controller: _secretKeyController,
              enabled: !_loadingSettings && !_busy && !_recording,
              obscureText: _obscureSecretKey,
              decoration: InputDecoration(
                labelText: 'SecretKey (SK)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscureSecretKey = !_obscureSecretKey,
                  ),
                  icon: Icon(
                    _obscureSecretKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _obscureSecretKey ? '显示密钥' : '隐藏密钥',
                ),
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: SpacingTokens.sm),
            TextButton.icon(
              onPressed: _loadingSettings || _busy || _recording
                  ? null
                  : () => setState(
                        () => _showRealtimeSettings = !_showRealtimeSettings,
                      ),
              icon: Icon(
                _showRealtimeSettings ? Icons.expand_less : Icons.expand_more,
              ),
              label: const Text('高级设置：手动填写 APPID'),
            ),
            if (_showRealtimeSettings) ...[
              TextField(
                controller: _appIdController,
                enabled: !_loadingSettings && !_busy && !_recording,
                decoration: const InputDecoration(
                  labelText: 'APPID',
                  prefixIcon: Icon(Icons.swap_horiz_outlined),
                  helperText: '默认自动获取；无法获取时可从腾讯云账号信息页复制填写',
                ),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
              ),
            ],
            const SizedBox(height: SpacingTokens.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _loadingSettings || _busy || _recording
                    ? null
                    : _saveCredentials,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存密钥'),
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            Text(
              '优先使用实时识别，仅当实时资源包耗尽时切换为一句话识别。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: SpacingTokens.sm),
            ColoredCard(
              color: theme.colorScheme.primary,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: [
                      Icon(
                        settings.isVerified
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 20,
                        color: settings.isVerified
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: SpacingTokens.xs),
                      Expanded(
                        child: Text(
                          settings.isVerified
                              ? '已配置 · 跟读评分可用'
                              : settings.hasCredentials
                                  ? '密钥已保存 · 认字可用，跟读需完成录音测试'
                                  : '未配置 · 跟读功能需先填写密钥并通过测试',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    '真实录音测试',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.xs),
                  Text(
                    _testPhrase,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loadingSettings || _busy
                          ? null
                          : _recording
                              ? _finishTest
                              : _startTest,
                      icon: Icon(
                        _recording ? Icons.stop : Icons.mic_none_outlined,
                      ),
                      label: Text(testButtonLabel),
                    ),
                  ),
                  if (_recording) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancelTest,
                        icon: const Icon(Icons.close),
                        label: const Text('取消测试'),
                      ),
                    ),
                  ],
                  if (_usedSentenceFallback) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      _hasTestResult
                          ? '实时识别额度已用完，本次使用一句话识别。'
                          : '实时识别额度已用完，将在录音结束后识别。',
                    ),
                  ],
                  if (_liveText.isNotEmpty) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      _hasTestResult ? '系统识别到的文字' : '正在识别的文字',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: SpacingTokens.xs),
                    Text(
                      _liveText,
                      key: const ValueKey('speech-test-live-transcript'),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: SpacingTokens.sm),
              Text(
                _message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: statusColor,
                ),
              ),
            ],
            const SizedBox(height: SpacingTokens.md),
            Text(
              '录音仅在测试、跟读或认字时处理。腾讯云额度与费用以腾讯云账户状态为准。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
