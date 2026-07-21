// lib/features/profile/speech_recognition_settings_page.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/speech/hybrid_speech_recognition_service.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/core/services/speech/tencent_asr_client.dart';
import 'package:poemath/core/theme/design_tokens.dart';
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
  SpeechRecognitionSettingsState? _settings;
  bool _obscureSecretKey = true;
  bool _busy = false;
  bool _recording = false;
  String _liveText = '';
  String? _message;
  bool _messageIsError = false;
  Timer? _recordingTimer;
  late final SpeechRecognitionService _speechService;

  @override
  void initState() {
    super.initState();
    _secretIdController = TextEditingController();
    _secretKeyController = TextEditingController();
    _speechService = ref.read(speechRecognitionServiceProvider);
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final repo = ref.read(settingsRepositoryProvider);
    final credentials = await repo.readTencentAsrCredentials();
    final settings = await repo.loadSpeechRecognitionSettings();
    if (!mounted) return;
    _secretIdController.text = credentials?.secretId ?? '';
    _secretKeyController.text = credentials?.secretKey ?? '';
    setState(() => _settings = settings);
  }

  TencentAsrCredentials? _readFormCredentials() {
    final credentials = TencentAsrCredentials(
      secretId: _secretIdController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
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
    return credentials;
  }

  Future<void> _saveCredentials() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final credentials = await _saveFormCredentials();
      if (credentials == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _loadSettings();
      if (mounted) _showMessage('密钥已保存，需重新完成真实录音测试');
    } on Object {
      if (mounted) _showMessage('密钥保存失败，请稍后重试', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTest() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _message = null;
      _liveText = '';
    });
    try {
      final credentials = await _saveFormCredentials();
      if (credentials == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _speechService.initialize();
      await _speechService.start(
        onPartialResult: (text) {
          if (mounted) setState(() => _liveText = text);
        },
      );
      if (!mounted) {
        await _speechService.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _busy = false;
        _message = '请朗读：$_testPhrase';
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
      final result = await _speechService.stop(requireTencentCloud: true);
      await repo.markTencentAsrCredentialsVerified(
        testedCredentials: credentials,
      );
      await _loadSettings();
      if (mounted) {
        _showMessage(
          result.text.isEmpty ? '测试未返回文字' : '测试成功，可开启高精度识别',
        );
      }
    } on TencentAsrException catch (error) {
      await _invalidateAfterFailedTest();
      if (mounted) _showMessage(error.message, isError: true);
    } on SpeechRecognitionException catch (error) {
      await _invalidateAfterFailedTest();
      if (mounted) _showMessage(error.message, isError: true);
    } on Object {
      await _invalidateAfterFailedTest();
      if (mounted) _showMessage('测试失败，已保持离线识别', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invalidateAfterFailedTest() async {
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
    await _speechService.cancel();
    await _invalidateAfterFailedTest();
    if (mounted) {
      setState(() {
        _recording = false;
        _busy = false;
      });
      _showMessage('测试已取消，继续使用离线识别', isError: true);
    }
  }

  Future<void> _toggleHighAccuracy(bool enabled) async {
    if (_busy || _recording) return;
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setTencentAsrHighAccuracyEnabled(enabled);
      await _loadSettings();
      if (mounted) {
        _showMessage(enabled ? '已开启高精度识别' : '已关闭高精度识别');
      }
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } on Object {
      if (mounted) _showMessage('设置更新失败', isError: true);
    }
  }

  Future<void> _deleteCredentials() async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    try {
      await ref.read(settingsRepositoryProvider).deleteTencentAsrCredentials();
      _secretIdController.clear();
      _secretKeyController.clear();
      await _loadSettings();
      if (mounted) _showMessage('腾讯云密钥已删除，高精度识别已关闭');
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
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    if (_speechService.isRecording) unawaited(_speechService.cancel());
    _secretIdController.dispose();
    _secretKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('语音识别设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final statusColor =
        _messageIsError ? theme.colorScheme.error : theme.colorScheme.primary;
    final testButtonLabel = _recording ? '结束并验证' : '开始真实录音测试';

    return Scaffold(
      appBar: AppBar(
        title: const Text('语音识别设置'),
        actions: [
          IconButton(
            onPressed: _busy || _recording ? null : _deleteCredentials,
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除腾讯云密钥',
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          children: <Widget>[
            Text('腾讯云密钥', style: theme.textTheme.titleMedium),
            const SizedBox(height: SpacingTokens.sm),
            TextField(
              controller: _secretIdController,
              enabled: !_busy && !_recording,
              decoration: const InputDecoration(
                labelText: 'SecretId (AK)',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: SpacingTokens.sm),
            TextField(
              controller: _secretKeyController,
              enabled: !_busy && !_recording,
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
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy || _recording ? null : _saveCredentials,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存密钥'),
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            AppTile(
              icon: Icons.cloud_done_outlined,
              iconColor: settings.isVerified
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              title: '高精度云端识别',
              subtitle: settings.highAccuracyEnabled
                  ? '已开启 · 失败时自动回退离线识别'
                  : settings.isVerified
                      ? '测试已通过，当前未开启'
                      : '完成真实录音测试后可开启',
              trailing: Switch(
                value: settings.highAccuracyEnabled,
                onChanged: settings.isVerified && !_busy && !_recording
                    ? _toggleHighAccuracy
                    : null,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            ColoredCard(
              color: theme.colorScheme.primary,
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
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
                  const SizedBox(height: SpacingTokens.sm),
                  if (_liveText.isNotEmpty)
                    Text(
                      _liveText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: SpacingTokens.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy
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
              '录音仅在测试或跟读时处理。腾讯云额度与费用以腾讯云账户状态为准。',
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
