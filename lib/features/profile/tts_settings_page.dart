// lib/features/profile/tts_settings_page.dart
//
// 层级：features/profile
// 职责：TTS 音频设置子页面 — 音色选择 + 语速调节。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/tts_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';

class TtsSettingsPage extends ConsumerStatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  ConsumerState<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends ConsumerState<TtsSettingsPage> {
  late final TtsService _tts;
  List<Map<String, String>>? _voices;
  Map<String, String>? _selectedVoice;
  late double _speed;
  bool _loading = true;
  String? _loadError;

  static const _previewText = '床前明月光，疑是地上霜。';

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    _selectedVoice = settingsRepo.ttsVoice;
    _speed = settingsRepo.ttsSpeed;
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final voices = await _tts.getChineseVoices();
      if (mounted) {
        setState(() {
          _voices = voices;
          _loading = false;
        });
      }
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '加载系统音色失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _voices = const [];
          _loading = false;
          _loadError = '音色加载失败，请检查系统语音服务';
        });
      }
    }
  }

  Future<void> _selectVoice(Map<String, String>? voice) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      await _tts.stop();
      await _tts.setVoice(voice);
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        '保存 TTS 音色失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('音色设置失败，请稍后重试')),
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _selectedVoice = voice);
    }

    try {
      await _tts.preview(_previewText);
    } on Exception catch (error, stackTrace) {
      AppLogger.e(
        'TTS 音色试听失败',
        tag: 'TtsSettings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        scaffold.clearSnackBars();
        scaffold.showSnackBar(
          const SnackBar(content: Text('音色已保存，但试听失败')),
        );
      }
    }
  }

  Future<void> _onSpeedChanged(double speed) async {
    setState(() => _speed = speed);
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.setTtsSpeed(speed);
  }

  @override
  void dispose() {
    // 离开页面停止试听
    unawaited(
      _tts.stop().onError(
            (error, stackTrace) => AppLogger.e(
              '退出音频设置页时停止试听失败',
              tag: 'TtsSettings',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
    );
    super.dispose();
  }

  /// locale → 友好标签。
  static String _localeLabel(String locale) {
    if (locale.startsWith('zh-CN') || locale == 'zh_CN') return '普通话';
    if (locale.startsWith('zh-TW') || locale == 'zh_TW') return '台湾';
    if (locale.startsWith('zh-HK') || locale == 'zh_HK') return '粤语';
    if (locale.startsWith('zh')) return '中文';
    return locale;
  }

  /// 将原始 voice name 转为友好显示名。
  ///
  /// Android 上 name 可能只是 "zh"，需要映射为可读名称。
  /// 去重后如果只有一个音色，显示为「中文语音」即可。
  static String _voiceDisplayName(String name, String locale, int index) {
    // 如果 name 是有意义的（不是纯 locale code），直接用
    final lower = name.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
    final isLocaleCode = lower == 'zh' ||
        lower == 'zhcn' ||
        lower == 'zhtw' ||
        lower == 'zhhk' ||
        lower.isEmpty;

    if (!isLocaleCode) return name;

    // name 只是 locale code，生成友好名称
    final label = _localeLabel(locale);
    if (index == 0) return '$label语音';
    return '$label语音 ${index + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('音频设置')),
      body: SafeArea(
        child: AnimatedPageBody(
          children: [
            // ====== 语速调节 ======
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.speed,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      Text(
                        '语速调节',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                  Row(
                    children: [
                      Text(
                        '慢',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: _speed,
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          label: _speed.toStringAsFixed(1),
                          onChanged: _onSpeedChanged,
                        ),
                      ),
                      Text(
                        '快',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Text(
                      '当前语速：${_speed.toStringAsFixed(1)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: SpacingTokens.lg),

            // ====== 音色选择 ======
            Row(
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: SpacingTokens.sm),
                Text(
                  '音色选择',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '点击试听',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SpacingTokens.sm),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(SpacingTokens.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(SpacingTokens.xl),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.record_voice_over_outlined,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: SpacingTokens.md),
                      OutlinedButton.icon(
                        onPressed: _loadVoices,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新加载'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // 系统默认
              _buildVoiceTile(
                theme: theme,
                title: '系统默认',
                subtitle: '使用系统默认中文语音',
                icon: Icons.auto_awesome,
                isSelected: _selectedVoice == null,
                onTap: () => _selectVoice(null),
              ),

              if (_voices!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(SpacingTokens.xl),
                  child: Center(
                    child: Text(
                      '未找到中文语音\n请在系统设置中下载中文语音包',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else
                ..._voices!.asMap().entries.map((entry) {
                  final index = entry.key;
                  final voice = entry.value;
                  final isSelected = _selectedVoice != null &&
                      _selectedVoice!['name'] == voice['name'] &&
                      _selectedVoice!['locale'] == voice['locale'];
                  final name = voice['name'] ?? '';
                  final locale = voice['locale'] ?? '';
                  return _buildVoiceTile(
                    theme: theme,
                    title: _voiceDisplayName(name, locale, index),
                    subtitle: _localeLabel(locale),
                    icon: Icons.record_voice_over,
                    isSelected: isSelected,
                    onTap: () => _selectVoice(voice),
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: AppTile(
        icon: isSelected ? Icons.check_circle : icon,
        iconColor:
            isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
        title: title,
        subtitle: subtitle,
        trailing: IconButton(
          icon: Icon(
            Icons.play_circle_outline,
            color: theme.colorScheme.primary,
          ),
          tooltip: '试听',
          onPressed: onTap,
        ),
        onTap: onTap,
      ),
    );
  }
}
